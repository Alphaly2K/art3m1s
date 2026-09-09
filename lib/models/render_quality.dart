enum RenderQualityPreset {
  native('原生', 0),
  quality('质量', 1),
  balanced('均衡', 2),
  performance('性能', 3);

  const RenderQualityPreset(this.label, this.ffiValue);
  final String label;
  final int ffiValue;
}
