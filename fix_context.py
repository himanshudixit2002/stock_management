import re
import os

with open('analyze_results.txt', 'r') as f:
    lines = f.readlines()

fixes_by_file = {}

for line in lines:
    if 'use_build_context_synchronously' in line:
        # Example: info • Don't use 'BuildContext's across async gaps • lib/screens/inventory/stock_take_count_screen.dart:158:27 • use_build_context_synchronously
        parts = line.split(' • ')
        if len(parts) >= 3:
            file_info = parts[2].strip()
            # lib/screens/inventory/stock_take_count_screen.dart:158:27
            file_parts = file_info.split(':')
            if len(file_parts) >= 2:
                filepath = file_parts[0]
                line_num = int(file_parts[1]) - 1 # 0-indexed
                
                if filepath not in fixes_by_file:
                    fixes_by_file[filepath] = []
                fixes_by_file[filepath].append(line_num)

for filepath, line_nums in fixes_by_file.items():
    if not os.path.exists(filepath):
        continue
    
    with open(filepath, 'r') as f:
        file_lines = f.readlines()
        
    # Sort descending so inserting doesn't change previous line numbers
    line_nums = sorted(list(set(line_nums)), reverse=True)
    
    for ln in line_nums:
        if ln < len(file_lines):
            # Find indentation
            original_line = file_lines[ln]
            indent = len(original_line) - len(original_line.lstrip())
            indent_str = ' ' * indent
            
            # Check if we are inside a State class. If so, `mounted` is available.
            # If not, we might need `context.mounted`.
            # A simple heuristic: if it's a provider or a function that takes BuildContext context, use context.mounted.
            # But let's just insert `if (!mounted) return;` for now, if it fails compilation, we'll fix it.
            
            # Actually, `if (!mounted) return;` is best for StatefulWidget.
            # Let's try `if (!mounted) return;` first.
            injection = f"{indent_str}if (!mounted) return;\n"
            file_lines.insert(ln, injection)
            
    with open(filepath, 'w') as f:
        f.writelines(file_lines)

print("Injected mounted checks!")
