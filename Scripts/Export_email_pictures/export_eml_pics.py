import email
import os
from email import policy
import tkinter as tk
from tkinter import filedialog

# ====== 过滤小图片阈值（字节）======
MIN_IMAGE_SIZE = 10 * 1024   # 10KB


# 隐藏主窗口
root = tk.Tk()
root.withdraw()

# 选择 eml 文件
eml_files = filedialog.askopenfilenames(
    title="选择 .eml 文件",
    filetypes=[("EML files", "*.eml")]
)

if not eml_files:
    print("未选择文件，程序退出")
    exit()


# 防止文件名重复
def get_unique_filename(directory, filename):
    base, ext = os.path.splitext(filename)
    counter = 1
    new_filename = filename

    while os.path.exists(os.path.join(directory, new_filename)):
        new_filename = f"{base}_{counter}{ext}"
        counter += 1

    return new_filename


total_files = len(eml_files)

print(f"\n开始处理 {total_files} 个邮件...\n")


# ==============================
# 遍历每个 eml 文件
# ==============================

for index, eml_file in enumerate(eml_files, start=1):

    print(f"[{index}/{total_files}] 处理邮件: {os.path.basename(eml_file)}")

    # 源文件所在目录
    source_dir = os.path.dirname(eml_file)

    # exported_images 目录
    export_root = os.path.join(source_dir, "exported_images")
    os.makedirs(export_root, exist_ok=True)

    # 每个邮件一个子目录
    mail_name = os.path.splitext(os.path.basename(eml_file))[0]
    mail_output_dir = os.path.join(export_root, mail_name)
    os.makedirs(mail_output_dir, exist_ok=True)

    saved_count = 0

    # 读取邮件
    with open(eml_file, "rb") as f:
        msg = email.message_from_binary_file(f, policy=policy.default)

    # 遍历邮件内容
    for i, part in enumerate(msg.walk()):

        content_type = part.get_content_type()

        if not content_type.startswith("image/"):
            continue

        data = part.get_payload(decode=True)

        if not data:
            continue

        # ====== 过滤小图片 ======
        if len(data) < MIN_IMAGE_SIZE:
            continue

        filename = part.get_filename()

        # 没有文件名时自动生成
        if not filename:
            ext = content_type.split("/")[1]
            filename = f"image_{i}.{ext}"

        filename = get_unique_filename(mail_output_dir, filename)

        filepath = os.path.join(mail_output_dir, filename)

        with open(filepath, "wb") as img:
            img.write(data)

        saved_count += 1

    print(f"   ✔ 提取图片 {saved_count} 张\n")


print("所有邮件处理完成！")