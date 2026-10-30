# Rust 依赖许可文本

此目录为许可证导出工具提供缺失的标准许可全文，最终声明写入应用共享的
`assets/licenses/rust_third_party.json`。依赖来源与版本由 Cargo metadata 确定。

- Apache-2.0：<https://www.apache.org/licenses/LICENSE-2.0.txt>；无独立许可文件的双许可依赖选择 Apache-2.0。
- LGPL-2.1-or-later：<https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>；保留 Siglus WMA Professional 模块的单独许可声明。

发布含 LGPL 模块的二进制时，须同时提供对应源代码、构建与重新链接所需材料，
保留版权及许可声明，并允许为调试这些模块的修改而进行逆向工程。
KRKRSDL3 及原生编解码依赖的声明也须随各平台发布包保留。
