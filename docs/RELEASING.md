# 发布与构建

Mod：假兔脚（Mimick Rabbitfoot）。游戏内部目录与设置前缀继续使用
`interesting_seed_filter`，避免破坏 Noita 虚拟路径和玩家已有设置。

- [GitHub 公共仓库](https://github.com/BunnyCiela/Mimick-Rabbitfoot)
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

创意工坊的内容上传配置是Mod根目录 `workshop.xml`，主视觉为用户提供的
`workshop_preview_image.png`。上传排除项覆盖开发资料和非运行期工具；
`tools/foundation/diagnostics/*.lua` 仍是入口代码引用的可选模块，默认关闭。
MIT许可和第三方声明另以根目录 `.txt` 副本随工坊上传，符合上传器扩展名白名单。

**工坊标题与介绍按语言分别维护，不能把中英文合并到同一描述。**
`tools/release/workshop-locales.json`保存Steam的`english`与`schinese`两套元数据：
英文标题`Mimick Rabbitfoot`，简体中文标题`假兔脚`，各自使用对应语言介绍。
这是工坊页面的语言，与Mod内11种界面语言相互独立；未提供页面翻译的语言回退英文。

`workshop.xml`使用英文默认标题，`description`留空，避免内容上传覆盖已经发布的
分语言介绍。原上传器不解码XML实体，不能再通过该字段合并上传多语言文案。
默认英文回退及中文标题/介绍均已通过公开页面/API核对。

通过Noita附带Steam API的`SetItemUpdateLanguage`、`SetItemTitle`、
`SetItemDescription`发布每套元数据，不更新内容、主视觉、标签或可见性。
需要已登录的Steam和32位Windows PowerShell；脚本缺省只验证接口与文案，
只有指定`-Publish`才提交更新：

```powershell
& "$env:WINDIR/SysWOW64/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -File tools/release/publish_workshop_locales.ps1 -GameDirectory "D:/SteamLibrary/steamapps/common/Noita" -WorkshopId 3825300539 -Publish
```

脚本核对应用881100、Noita使用的UGC013/Utils009接口、Steam结果和目标条目ID。
不需要读取或导出登录凭据。Steam API成功后仍须检查公开页面的`l=english`和
`l=schinese`版本，确保标题和正文均分开。相关API规范见
[Steamworks ISteamUGC](https://partner.steamgames.com/doc/api/isteamugc#SetItemUpdateLanguage)。

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

设置页由`tools/release/settings.template.lua`生成，内置同一份语言表和解析器。
不要在生成后的`settings.lua`直接修改文案；Noita的部分设置环境不能读Mod其他文件，
因此设置页不依赖`dofile_once`或启用状态。生成器同时更新运行期catalog和设置页。
