import argparse
import os
import re
import subprocess
import sys

SKIP_DIRS = {
    'external/llvm-project',
    'packages/apps/Settings',
    'packages/apps/SetupWizard',
    'packages/apps/LineageCustomizer',
    'device/google/atv',
    'packages/modules/adb',
    'system/security',
}
SKIP_FILES = {
    'bionic': {'0006'},
    'system/linkerconfig': {'0003'},
    'frameworks/av': {'0028'},
    'system/core': {'0019'},
}
SECOND_STAGE = (
    ('frameworks/base', ('0001', '0003')),
    ('frameworks/native', ('0001', '0002', '0003', '0009')),
    ('system/core', ('0001', '0003', '0017', '0022')),
    ('system/vold', ('0004',)),
    ('external/selinux', None),
    ('system/hwservicemanager', None),
    ('system/libhwbinder', None),
    ('lineage-sdk', None),
)
SECOND_STAGE_NUMBERS = dict(SECOND_STAGE)
COMMITTER = ('OpenWave Patcher', 'patcher@openwave.invalid')
COMMIT_DATE = '1700000000 +0000'


def subject_of(path):
    with open(path, errors='replace') as stream:
        lines = stream.read().splitlines()
    for index, line in enumerate(lines):
        if line.startswith('Subject:'):
            text = line
            for follow in lines[index + 1:]:
                if follow.startswith((' ', '\t')):
                    text += ' ' + follow.strip()
                else:
                    break
            return re.sub(r'^Subject: (\[PATCH[^\]]*\] )?', '', text.strip())
    return ''


def patches_in(directory):
    if not os.path.isdir(directory):
        return []
    return sorted(name for name in os.listdir(directory) if name.endswith('.patch'))


def projects_in(root):
    found = []
    for base, _, files in os.walk(root):
        if any(name.endswith('.patch') for name in files):
            found.append(os.path.relpath(base, root))
    return sorted(found)


def build_plan(tree, openwave_dir):
    root = os.path.join(tree, 'vendor', 'extra', 'waydroid-patches', 'base-patches-37')
    first, second, third = [], [], []
    for project in projects_in(root):
        if project in SKIP_DIRS:
            continue
        later = SECOND_STAGE_NUMBERS.get(project, ())
        if later is None:
            continue
        for name in patches_in(os.path.join(root, project)):
            if name[:4] in SKIP_FILES.get(project, ()) or name[:4] in later:
                continue
            first.append((project, os.path.join(root, project, name)))
    for project, numbers in SECOND_STAGE:
        for name in patches_in(os.path.join(root, project)):
            if numbers is None or name[:4] in numbers:
                second.append((project, os.path.join(root, project, name)))
    for project in projects_in(openwave_dir):
        for name in patches_in(os.path.join(openwave_dir, project)):
            third.append((project, os.path.join(openwave_dir, project, name)))
    return [('waydroid patch set', first), ('approved security patches', second), ('openwave patches', third)]


def git(tree, project, *args):
    env = dict(os.environ)
    env.update({
        'GIT_COMMITTER_NAME': COMMITTER[0],
        'GIT_COMMITTER_EMAIL': COMMITTER[1],
        'GIT_COMMITTER_DATE': COMMIT_DATE,
    })
    return subprocess.run(['git', '-C', os.path.join(tree, project), *args], capture_output=True, text=True, env=env)


def applied_subjects(tree, project):
    result = git(tree, project, 'log', '--pretty=%s', '-n', '1000')
    return set(result.stdout.splitlines()) if result.returncode == 0 else set()


def is_project(tree, project):
    return os.path.exists(os.path.join(tree, project, '.git'))


def run(tree, openwave_dir, apply_changes):
    plan = build_plan(tree, openwave_dir)
    cache = {}
    counts = {'APPLIED': 0, 'PENDING': 0, 'MISSING': 0, 'FAILED': 0}
    for stage, entries in plan:
        print('== %s (%d patches)' % (stage, len(entries)))
        for project, path in entries:
            name = os.path.basename(path)
            if not is_project(tree, project):
                counts['MISSING'] += 1
                print('MISSING %s %s' % (project, name))
                continue
            if project not in cache:
                cache[project] = applied_subjects(tree, project)
            if subject_of(path) in cache[project]:
                counts['APPLIED'] += 1
                print('APPLIED %s %s' % (project, name))
                continue
            if not apply_changes:
                counts['PENDING'] += 1
                print('PENDING %s %s' % (project, name))
                continue
            if git(tree, project, 'status', '--porcelain', '--untracked-files=no').stdout.strip():
                counts['FAILED'] += 1
                print('FAILED %s %s (the project has uncommitted changes)' % (project, name))
                continue
            result = git(tree, project, 'am', '-3', '--no-gpg-sign', path)
            if result.returncode:
                git(tree, project, 'am', '--abort')
                counts['FAILED'] += 1
                print('FAILED %s %s: %s' % (project, name, (result.stdout + result.stderr).strip()[-300:]))
            else:
                cache[project].add(subject_of(path))
                counts['APPLIED'] += 1
                print('APPLIED-NOW %s %s' % (project, name))
    print('SUMMARY ' + ' '.join('%s=%d' % item for item in counts.items()))
    return counts


def main(argv):
    parser = argparse.ArgumentParser(description='Apply the OpenWave Android patch set to a synced source tree. '
                                                 'Idempotent: patches whose subject is already in the project '
                                                 'history are skipped.')
    parser.add_argument('command', choices=('check', 'apply'))
    parser.add_argument('--tree', required=True)
    parser.add_argument('--patches', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'patches', 'openwave'))
    args = parser.parse_args(argv)
    counts = run(os.path.abspath(args.tree), os.path.abspath(args.patches), args.command == 'apply')
    if counts['FAILED'] or counts['MISSING']:
        return 1
    if args.command == 'check' and counts['PENDING']:
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
