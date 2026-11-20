import argparse
import copy
import urllib.parse
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

LOCAL_COMMITTERS = {'OpenWave Patcher'}
LOCAL_ADDITIONS = ('02-waydroid.xml', '99-openwave-fixes.xml')
LOCAL_REMOVALS = ('01-removes.xml', '99-openwave-exclusions.xml', '99-openwave-fixes.xml')
LOCAL_REMOTES = '00-remotes.xml'


def git(*args, cwd=None):
    result = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)
    return result.returncode, result.stdout.strip()


def project_sha(tree, path, counts=None):
    directory = os.path.join(tree, path)
    if not os.path.exists(os.path.join(directory, '.git')):
        return None
    code, out = git('log', '--format=%H %cn', '-n', '2000', 'HEAD', cwd=directory)
    if code != 0 or not out:
        return None
    local = 0
    for line in out.splitlines():
        sha, committer = line.split(' ', 1)
        if committer not in LOCAL_COMMITTERS:
            if counts is not None and local:
                counts[path] = local
            return sha
        local += 1
    return None


def load_flat(manifest_dir, name):
    root = ET.parse(os.path.join(manifest_dir, name)).getroot()
    flat = ET.Element(root.tag, root.attrib)
    for child in root:
        if child.tag == 'include':
            included = load_flat(manifest_dir, child.get('name'))
            for item in included:
                flat.append(item)
        else:
            flat.append(child)
    return flat


def remote_url(remotes, manifest_url, name):
    remote = remotes[name]
    fetch = remote.get('fetch')
    if fetch.startswith('..'):
        fetch = urllib.parse.urljoin(manifest_url, fetch)
    return fetch.rstrip('/')


def resolve_remote(url, name, revision):
    refs = [revision, revision + '^{}'] if revision.startswith('refs/tags/') else [revision]
    code, out = git('ls-remote', url + '/' + name, *refs)
    if code != 0 or not out:
        return None
    lines = [line.split('\t') for line in out.splitlines()]
    peeled = [sha for sha, ref in lines if ref.endswith('^{}')]
    return (peeled or [lines[0][0]])[0]


def pretty(root):
    ET.indent(root, space='  ')
    return ET.tostring(root, encoding='unicode') + '\n'


def local_root(manifest_dir, name):
    return ET.parse(os.path.join(manifest_dir, '..', 'local_manifests', name)).getroot()


def build_default(tree, manifest_dir, manifest_url, report):
    flat = load_flat(manifest_dir, 'default.xml')
    remotes = {remote.get('name'): remote for remote in flat.iter('remote')}
    default = flat.find('default')
    out = ET.Element('manifest')
    for tag in ('remote', 'default', 'contactinfo'):
        for element in flat.findall(tag):
            element = copy.deepcopy(element)
            if tag == 'remote' and element.get('fetch', '').startswith('..'):
                element.set('fetch', remote_url(remotes, manifest_url, element.get('name')))
            out.append(element)
    for project in flat.findall('project'):
        path = project.get('path') or project.get('name')
        revision = project.get('revision') or remotes[project.get('remote') or default.get('remote')].get('revision') \
            or default.get('revision')
        sha = project_sha(tree, path, report['local_commits'])
        source = 'tree'
        if sha is None:
            remote = project.get('remote') or default.get('remote')
            sha = resolve_remote(remote_url(remotes, manifest_url, remote), project.get('name'), revision)
            source = 'ls-remote'
        if sha is None:
            report['unresolved'].append(path)
            continue
        report[source].append(path)
        item = copy.deepcopy(project)
        item.set('revision', sha)
        if not (len(revision) == 40 and all(c in '0123456789abcdef' for c in revision)):
            item.set('upstream', revision)
        out.append(item)
    return out


def removed_names(manifest_dir):
    names = []
    for name in LOCAL_REMOVALS:
        for element in local_root(manifest_dir, name).findall('remove-project'):
            names.append(element.get('name'))
    return names


def build_local(tree, manifest_dir, report, default):
    out = ET.Element('manifest')
    for element in local_root(manifest_dir, LOCAL_REMOTES).findall('remote'):
        out.append(copy.deepcopy(element))
    removals = removed_names(manifest_dir)
    added = {}
    for name in LOCAL_ADDITIONS:
        for project in local_root(manifest_dir, name).findall('project'):
            added[project.get('path') or project.get('name')] = project
    excluded_projects = {n for n in removals}
    for path, project in list(added.items()):
        if project.get('name') in excluded_projects:
            del added[path]
    present = {project.get('name') for project in default.findall('project')}
    for name in removals:
        if name not in present:
            continue
        element = ET.SubElement(out, 'remove-project')
        element.set('name', name)
    for path, project in added.items():
        sha = project_sha(tree, path, report['local_commits'])
        if sha is None:
            report['local_unresolved'].append(path)
            continue
        item = copy.deepcopy(project)
        revision = item.get('revision')
        item.set('revision', sha)
        if revision and not (len(revision) == 40 and all(c in '0123456789abcdef' for c in revision)):
            item.set('upstream', revision)
        out.append(item)
    return out


def main(argv):
    parser = argparse.ArgumentParser(description='Pin the LineageOS manifest and the OpenWave local manifest to the '
                                                 'upstream commits of an already synced tree.')
    parser.add_argument('--tree', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--committer')
    args = parser.parse_args(argv)
    tree = os.path.abspath(args.tree)
    manifest_dir = os.path.join(tree, '.repo', 'manifests')
    code, url = git('config', '--get', 'remote.origin.url', cwd=manifest_dir)
    manifest_url = url if code == 0 and url else 'https://github.com/LineageOS/android.git'
    LOCAL_COMMITTERS.add(args.committer or git('config', '--get', 'user.name')[1])
    report = {key: [] for key in ('tree', 'ls-remote', 'unresolved', 'local_unresolved')}
    report['local_commits'] = {}
    default = build_default(tree, manifest_dir, manifest_url, report)
    local = build_local(tree, manifest_dir, report, default)
    os.makedirs(os.path.join(args.out, 'local_manifests'), exist_ok=True)
    with open(os.path.join(args.out, 'default.xml'), 'w', encoding='utf-8') as stream:
        stream.write('<?xml version="1.0" encoding="UTF-8"?>\n' + pretty(default))
    with open(os.path.join(args.out, 'local_manifests', 'openwave.xml'), 'w', encoding='utf-8') as stream:
        stream.write('<?xml version="1.0" encoding="UTF-8"?>\n' + pretty(local))
    print('projects pinned from the tree:', len(report['tree']))
    print('projects pinned with git ls-remote (not in the tree):', len(report['ls-remote']), report['ls-remote'])
    print('unresolved default projects:', len(report['unresolved']), report['unresolved'])
    print('unresolved local projects:', len(report['local_unresolved']), report['local_unresolved'])
    print('projects carrying local commits:', len(report['local_commits']))
    for path, count in sorted(report['local_commits'].items()):
        print('  %-36s %d local commit(s) below the pin' % (path, count))
    return 1 if report['unresolved'] or report['local_unresolved'] else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
