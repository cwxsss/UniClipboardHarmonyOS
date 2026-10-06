# 中继配置自动检查与恢复重试（2026-10-06）

交付版本1.0.23 /1000024，已签名并HDC覆盖安装，用户确认原中继地址保存成功；只读settings.json确认allow_relay_fallback=true，custom_relay_urls=[https://relay.chatsss.top]。未卸载或清空手机应用数据。新版本日志未检出settings update failed或ERROR。

保存前宿主检查仅访问relay_configuration:transaction:v1：已知错误空索引按1.0.22规则清理；正常记录不删除，由Engine在现有mutation_gate事务锁内恢复。配对、历史、其他安全存储项和现有配置不进行重置。

update_network_settings遇到internal /1392错误且运行时仍RUNNING时最多自动重试一次。重试也重新检查事务；地址错误、访问拒绝、引擎不运行、其他错误码不自动重试。持续失败保留错误及待恢复记录，交给现有Engine事务恢复机制；不通过删除有效事务掩盖错误。界面区分无效地址、存储访问被拒绝、恢复重试后写入失败，并引导查看诊断。

验证：实际ArkTS源码VM运行时22项通过，新增首次失败后成功、两次失败停止、无效地址不重试、权限拒绝不写入、运行时停止不重试；安全存储10项通过。原鸿蒙源码回写后的22项亦通过。HAP release BUILD SUCCESSFUL，签名和覆盖安装成功。真机正常保存通过；故障注入重试路径由VM边界替身验证，未在真机故意损坏有效事务。

源码回写9文件，写前哈希核对、备份relay-auto-recovery-original-backup。未改原Engine仓库，未提交/推送/发布。

签名包UniClipboard-HarmonyOS-1.0.23-UniPC-signed.hap，SHA256=9ed1aaae0c1d35cea9411a7356bce754b7282fd805b122d927229a8244929cf5。

后续触发条件：若出现其他格式的损坏事务，应先验证记录可恢复性再扩大修复规则；不能自动删除含有效回滚数据的记录。中继服务连接与跨设备双向直接粘贴属于另一项真机验收，不能从配置保存成功推导通过。
