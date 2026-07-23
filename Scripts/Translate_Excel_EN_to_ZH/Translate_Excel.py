#依赖pip install pandas openpyxl deep_translator tqdm
import os
import pandas as pd
from deep_translator import GoogleTranslator
from tkinter import Tk, filedialog
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed

# 隐藏主窗口
root = Tk()
root.withdraw()

# 弹窗选择多个 Excel 文件
file_paths = filedialog.askopenfilenames(
    title="选择需要翻译的Excel文件",
    filetypes=[("Excel files", "*.xlsx *.xls")]
)

if not file_paths:
    print("未选择文件")
    exit()

translator = GoogleTranslator(source='en', target='zh-CN')

# 多线程翻译函数
def translate_text(val):
    try:
        val_str = str(val).strip()
        if val_str:
            return translator.translate(val_str)
        else:
            return val
    except Exception as e:
        print(f"翻译错误: {val} -> {e}")
        return val

for file_path in file_paths:
    print(f"\n正在处理: {file_path}")

    df = pd.read_excel(file_path)

    for col in df.columns:
        new_col = f"{col}_CN"
        print(f"  翻译列: {col}")

        # 缓存重复文本
        cache = {}

        # 获取列内容
        col_values = df[col].tolist()

        # 过滤非空文本并去重
        unique_values = list(set([str(v) for v in col_values if str(v).strip() != ""]))
        print(f"    批量翻译 {len(unique_values)} 条唯一内容")

        # 多线程翻译唯一文本
        with ThreadPoolExecutor(max_workers=8) as executor:
            future_to_val = {executor.submit(translate_text, val): val for val in unique_values}
            for future in tqdm(as_completed(future_to_val), total=len(unique_values), desc="    批量进度", ncols=80):
                val = future_to_val[future]
                cache[val] = future.result()

        # 使用缓存生成中文列
        translated_values = []
        for v in col_values:
            v_str = str(v)
            if v_str.strip() != "":
                translated_values.append(cache.get(v_str, v))
            else:
                translated_values.append(v)
        df[new_col] = translated_values

    # 创建 translated 文件夹
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "translated")
    os.makedirs(output_dir, exist_ok=True)

    file_name = os.path.basename(file_path)
    output_path = os.path.join(output_dir, file_name)
    df.to_excel(output_path, index=False)

    print(f"已保存到: {output_path}")

print("\n全部文件翻译完成！")