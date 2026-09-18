# Solution — Unstoppable Wallet 的二次开发分支

## 这是什么

基于 [horizontalsystems/unstoppable-wallet-ios](https://github.com/horizontalsystems/unstoppable-wallet-ios)（MIT）的分支，
面向**自用侧载**，加三样上游没有的能力：

1. **任意币付 gas** —— EIP-7702 把现有 EOA 升级成智能账户（地址不变），之后用 USDT/USDC 付手续费
2. **24 词助记词账户** —— 大多数手机钱包只给 12 词
3. **通用 Safe 智能账户支持** —— 用 owner 私钥直接操作任意 Safe（含 Zodiac Delay 模块的两步出金）

上游的钱包、多链、DEX 兑换、行情、NFT、WalletConnect 全部保留不动。

## 为什么选这个上游

对比过的候选与排除原因：

- **Rainbow**（GPL-3）：postinstall 依赖私有仓库 `rainbow-me/rainbow-scripts`，`yarn install` 都跑不完；
  价格/余额/NFT 全走自家付费 provider，官方在 fork 说明里明确表示没有开源 API key 可提供。
- **OneKey**：自定义 O-SSL 许可，需要法务判断；同样绑自家后端。
- **MetaMask Mobile**：2020 年起改为专有许可。

Unstoppable 的关键优势：MIT、纯原生 Swift、`git clone` + 一个 xcconfig 就能构建、**没有私有仓库依赖**。

## 开发环境的特殊约束

开发机是 **Windows**，装不了 Xcode。因此：

- **构建只在 CI 上做**（GitHub Actions 的 macOS runner）
- **界面靠 CI 截图验证** —— `.github/scripts/shoot.sh` 在模拟器里启动 App 并截图，作为 artifact 传回
- **不手改 `project.pbxproj`** —— 幸运的是上游用了 Xcode 16 的
  `PBXFileSystemSynchronizedRootGroup`，`Unstoppable/`、`Tests/`、`Widget/`、`Intents/`
  这几个目录是文件系统同步组，**新增 .swift 文件直接丢进目录即可自动参与编译**
- 新增的独立模块一律做成 SPM 包（`Package.swift` 是纯文本，改起来安全）

## 构建

CI 自动跑，也可手动触发（Actions → 侧载构建 → Run workflow）。产物两个：

| Artifact | 用途 |
|---|---|
| `solution-unsigned-ipa` | 无签名 IPA，用 SideStore 在设备上签名安装 |
| `screenshots` | 模拟器截图，用于远程确认界面 |

失败时还会有 `xcodebuild-log`。

### 无签名 IPA 是怎么来的

不能用 `xcodebuild -exportArchive`——它的每种 exportMethod 都要求证书和 provisioning profile。
所以流程是：

```
xcodebuild archive  CODE_SIGNING_ALLOWED=NO CODE_SIGN_ENTITLEMENTS=""
  → 从 .xcarchive/Products/Applications 取出 .app
  → 放进 Payload/ 目录 zip 成 .ipa
```

`CODE_SIGN_ENTITLEMENTS=""` 是必须的：上游 entitlements 里有推送通知、关联域名、iCloud 容器，
**这些免费 Apple 证书一个都给不了**，带着它们 SideStore 重签会失败。

### API key

`Config.xcconfig` 被上游 gitignore（里面是 API key），由 `.github/scripts/make-xcconfig.sh`
从模板生成，取值来自 GitHub Secrets 里的 `XCCONFIG_<KEY>`。

**一个 key 都不填也能构建和启动**，只是部分数据源会降级（比如少一个交易历史来源）。
我们自己加的功能不依赖任何 key。

## 侧载

1. 从 Actions 下载 `solution-unsigned-ipa`
2. 用 SideStore 安装（首次配对需要电脑，Windows 可以）

注意事项：

- 免费 Apple 证书 **7 天过期**，需要 SideStore 定期刷新
- 免费账号有 **3 个 App 上限**；SideStore nightly + LiveContainer 可绕过
- **SideStore 刷新要占 iOS 唯一的 VPN 槽位**，与其他 VPN 互斥

## 与上游同步

```bash
git fetch upstream
git rebase upstream/master     # 我们的改动尽量集中在独立文件/SPM 包里，减少冲突面
```
