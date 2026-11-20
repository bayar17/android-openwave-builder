import argparse
import concurrent.futures
import os
import subprocess
import sys
import xml.etree.ElementTree as ET


def load(default_path, local_path):
    default = ET.parse(default_path).getroot()
    projects = {}
    for project in default.findall('project'):
        if 'notdefault' in (project.get('groups') or '').split(','):
            continue
        projects[project.get('path') or project.get('name')] = (project.get('name'), project.get('revision'))
    if local_path and os.path.exists(local_path):
        local = ET.parse(local_path).getroot()
        for removed in local.findall('remove-project'):
            for path in [path for path, value in projects.items() if value[0] == removed.get('name')]:
                del projects[path]
        for project in local.findall('project'):
            projects[project.get('path') or project.get('name')] = (project.get('name'), project.get('revision'))
    return projects


def git(tree, path, *args):
    result = subprocess.run(['git', '-C', os.path.join(tree, path)] + list(args), capture_output=True, text=True)
    return result.returncode, result.stdout.strip()


def classify(item, tree):
    path, (name, revision) = item
    if not os.path.isdir(os.path.join(tree, path, '.git')) and not os.path.isfile(os.path.join(tree, path, '.git')):
        return path, 'MISSING', revision
    code, head = git(tree, path, 'rev-parse', 'HEAD')
    if code != 0:
        return path, 'MISSING', revision
    if head == revision:
        return path, 'EXACT', head
    if revision and len(revision) == 40:
        code, _ = git(tree, path, 'merge-base', '--is-ancestor', revision, 'HEAD')
        if code == 0:
            return path, 'AHEAD', head
    return path, 'MISMATCH', head


def main(argv):
    parser = argparse.ArgumentParser(description='Compare the checked-out HEAD of every project with the pinned manifests.')
    parser.add_argument('--tree', required=True)
    parser.add_argument('--default', required=True)
    parser.add_argument('--local')
    parser.add_argument('--allow-ahead', action='store_true')
    args = parser.parse_args(argv)
    projects = load(args.default, args.local)
    tree = os.path.abspath(args.tree)
    counts = {'EXACT': 0, 'AHEAD': 0, 'MISMATCH': 0, 'MISSING': 0}
    bad = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for path, state, head in pool.map(lambda item: classify(item, tree), sorted(projects.items())):
            counts[state] += 1
            if state in ('MISMATCH', 'MISSING') or (state == 'AHEAD' and not args.allow_ahead):
                bad.append((state, path, projects[path][1], head))
    for state, path, pinned, head in bad[:40]:
        print('%s %s pinned=%s head=%s' % (state, path, pinned, head))
    if len(bad) > 40:
        print('... %d more' % (len(bad) - 40))
    print('SUMMARY projects=%d %s' % (len(projects), ' '.join('%s=%d' % item for item in counts.items())))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
