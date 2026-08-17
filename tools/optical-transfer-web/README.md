# UniClipboard 光学传输电脑端

这个网页工具与 HarmonyOS 端使用同一套 `UCO1` 动态二维码喷泉码协议，支持：

- 电脑选择文件或输入文字，通过屏幕发送给手机。
- 手机显示文字、图片或文件的动态二维码，通过电脑摄像头接收并下载。
- 不要求手机和电脑之间存在可用的网络连接。

## 启动

```powershell
cd D:\UniClipboardHarmonyOS\tools\optical-transfer-web
npm install
npm run dev -- --port 4173
```

命令行会显示电脑局域网 HTTPS 地址。第一次打开时需要接受开发证书提示。

- 电脑发送：`https://电脑IP:4173/send/`
- 电脑接收：`https://电脑IP:4173/receive/`

电脑接收时，必须允许浏览器使用摄像头。当前兼容模式单次最多传输 4 MB；动态二维码需要持续对准，不能只扫其中一张。

协议和喷泉码实现改编自 `bashalarmistalt/decimen-optical-transfer`，许可见项目根目录 `THIRD_PARTY_NOTICES.md`。
