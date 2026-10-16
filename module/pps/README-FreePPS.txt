内置 FreePPS 说明（GPL-3.0 合规声明）
=====================================

本目录中的 FreePPS 程序是 FreePPS v1.7.0，作者 Seyud（酷安@瓦力喀 / GitHub@Seyud），
以 GNU General Public License v3.0 或更高版本发布：
  上游源码：https://github.com/Seyud/FreePPS（标签 v1.7.0，提交 78e647d95f4a7456f7769b437cc5ca956b99cdbd）
  许可证全文：FreePPS-LICENSE；版权声明：FreePPS-NOTICES

由「小米/红米充电加速模块」（mi_charge_boost，作者 酷安@鱼楠）修改：
  只修改了 src/common/constants.rs 里的 4 个路径常量，改为本模块的私有目录
  /data/adb/mi_charge_boost/freepps/（free、disable、module.prop），程序逻辑未改动。
  补丁：freepps-paths.patch
  修改后的完整对应源码：FreePPS-src-v1.7.0-mcb.tar.gz（Cargo.toml、Cargo.lock、src、LICENSE、NOTICES、补丁）

构建方式：
  rustup target add aarch64-linux-android
  cargo build --locked --release --target aarch64-linux-android
  （链接器：Android NDK r29 sysroot，API 29；Cargo.toml 的 release 配置未改）

与本模块的对接（都在 daemon.sh / pps.sh 中，均不写 pd_verifed）：
  - WebUI「公版 PPS 解锁」开关（/data/adb/mi_charge_boost/pps）映射为 FreePPS 的 free 文件 1/0；
    本模块被禁用时映射为 0
  - 与 FreePPS 原版 service.sh 一样，等开机完成并且用户解锁后才启动
  - 已安装并启用 FreePPS 模块时，内置的 FreePPS 停止运行（让出）
  - FreePPS 的日志通过 logcat（tag FreePPS）保存到 /data/adb/mi_charge_boost/freepps.log

本模块其它部分不属于 FreePPS，FreePPS 的作者不对本模块负责。
FreePPS 不附带任何担保，详见 GPL-3.0。
