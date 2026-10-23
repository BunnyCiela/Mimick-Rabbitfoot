# 发布与构建

Mod：假兔脚（Mimick Rabbitfoot）。游戏内部目录与设置前缀继续使用
`interesting_seed_filter`，避免破坏 Noita 虚拟路径和玩家已有设置。

- [GitHub 公共仓库](https://github.com/CloudChaan/Mimick-Rabbitfoot)
- [Steam 创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3825300539)

本地开发 Mod 保留在 `mods/interesting_seed_filter`。整理后的独立 Git 仓库位于
游戏目录的 `mod-source/Mimick-Rabbitfoot`。开发目录中的 `.scratch` 包含历史需求、
测试记录和内部资料，不纳入公开源码或工坊上传；不得清理这些历史资料。

公开仓库采用 MIT 代码许可，保留第三方声明；游戏地图与其生成字节表不进 Git。
`tools/release/game_assets.json` 记录所需的167个原版图像路径和SHA-256。
在公开仓库运行：

```powershell
python tools/release/generate_locales.py --check
python tools/release/check_source.py
python tools/foundation/run_tests.py
python tools/release/build.py --wak "D:/SteamLibrary/steamapps/common/Noita/data/data.wak" --out dist/next/interesting_seed_filter
```

构建输出目录必须不存在。构建器核对全部游戏图像，然后生成沙盒可读的
`png_bytes.lua`、可玩的Mod目录和ZIP，不改变游戏存档或设置。

首次整理可用开发目录中的 `tools/release/export_source.py 新目录`，该脚本只复制白名单文件。
后续维护需将授权的源码改动同步到独立仓库，审阅差异、通过检查后提交推送。
不把本地游戏素材、存档、临时marker或统计缓存提交到仓库。

创意工坊的配置是Mod根目录 `workshop.xml`，主视觉为用户提供的
`workshop_preview_image.png`。上传排除项覆盖开发资料和非运行期工具；
`tools/foundation/diagnostics/*.lua` 仍是入口代码引用的可选模块，默认关闭。
MIT许可和第三方声明另以根目录 `.txt` 副本随工坊上传，符合上传器扩展名白名单。

**Noita上传器原样传递description属性文本，不解码XML实体。**
说明文案要用属性中的实际换行；不能让XML写入器把换行改成`&#10;`。
尽量避免需要实体转义的字符，英文游戏名使用“Rabbit and Steel”。
首次发布已验证：实体形式会在Steam页面显示为文字，实际换行则正常。

在游戏根目录执行官方批量上传器：

```powershell
./noita_dev.exe -workshop_upload interesting_seed_filter -workshop_upload_change_notes "Describe the update here."
```

上传器返回`Done!`后，读取本地`workshop_id.txt`并通过Steam公开页面或
`ISteamRemoteStorage/GetPublishedFileDetails/v1/`核对标题、可见性、描述和主视觉。
不得删除既有`workshop_id.txt`来更新，否则可能新建重复条目。

语言来源为游戏的`data/translations/common.csv`表头，共11种语言。
编辑`tools/release/locales.json`后重新生成catalog；运行时按游戏的
`$current_language`读取语言，设置界面每次绘制刷新文本。无读取接口时回退英文。
日志键、法术ID与诊断机器输出不翻译。
