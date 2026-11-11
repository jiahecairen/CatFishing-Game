class_name ConfigLoader
extends RefCounted
# CFG-001 实现：加载并校验 config/*.json（鱼种表、runtime_config）。
# 失败路径须明确：非法 species ID、负权重/价格、重复 ID、格式损坏一律拒绝，不发明默认值。
# 本票仅骨架，零实现，不创建任何 config/ 文件。
