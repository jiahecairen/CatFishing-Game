# Fishing AUTO-002 网页审批面板

将压缩包解压到：

`/Users/rain/DevGame/Fishing`

然后运行：

```bash
cd /Users/rain/DevGame/Fishing
python3 -m unittest discover -s tools/auto/ui -p 'test_*.py' -v
python3 tools/auto/ui/server.py
```

自动打开的浏览器页面就是控制台，使用鼠标查看、审核和批准工单。

**这是独立的网页前后端，不需要安装 pip 依赖。** 但当前无法直接读取你 Mac 上的 AUTO-001 源码，所以对于不匹配的真实审批字段会拒绝写入。完整安装与风险说明请看 `tools/auto/ui/README.md`。
