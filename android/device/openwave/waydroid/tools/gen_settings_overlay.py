import os
import re
import sys

TREE = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
SOURCE = os.path.join(TREE, 'packages/apps/Settings/res/xml')
TARGET = os.path.join(TREE, 'device/openwave/waydroid/overlay/packages/apps/Settings/res/xml')
FILES = (
    'top_level_settings.xml',
    'top_level_settings_expressive.xml',
    'top_level_settings_expressive_desktop.xml',
)
KEEP = {
    'top_level_apps',
    'top_level_storage',
    'top_level_system',
    'top_level_about_device',
    'top_level_privacy',
    'top_level_location',
    'top_level_accessibility',
}
ELEMENT = re.compile(r'[ \t]*<(?P<tag>[A-Za-z][\w.]*)(?P<attrs>(?:(?!<)[^>])*?android:key="(?P<key>top_level_[a-z_]+)"(?:(?!<)[^>])*?)/>[ \t]*\n', re.S)


def transform(text):
    removed = []

    def drop(match):
        if match.group('key') in KEEP or match.group('key').endswith('_category'):
            return match.group(0)
        removed.append(match.group('key'))
        return ''

    text = ELEMENT.sub(drop, text)
    return text, removed


def main():
    os.makedirs(TARGET, exist_ok=True)
    for name in FILES:
        with open(os.path.join(SOURCE, name), encoding='utf-8') as stream:
            original = stream.read()
        text, removed = transform(original)
        with open(os.path.join(TARGET, name), 'w', encoding='utf-8') as stream:
            stream.write(text)
        print(name, 'removed', len(removed), 'kept', len(KEEP & set(re.findall(r'android:key="(top_level_[a-z_]+)"', text))))
    return 0


if __name__ == '__main__':
    sys.exit(main())
