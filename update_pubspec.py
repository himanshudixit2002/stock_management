import re

with open('pubspec.yaml', 'r') as f:
    content = f.read()

replacement = """flutter_launcher_icons:
  android: true
  ios: true
  web:
    generate: true
    image_path: "logo.png"
    background_color: "#FFFFFF"
    theme_color: "#FFFFFF"
  image_path: "logo.png"
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "logo.png"
"""

content = re.sub(r'flutter_launcher_icons:\n(  .*\n)*', replacement, content)

with open('pubspec.yaml', 'w') as f:
    f.write(content)
