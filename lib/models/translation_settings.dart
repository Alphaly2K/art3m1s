enum TranslationMode {
  off,
  patch,
  online;

  String get label => switch (this) {
    TranslationMode.off => '关闭',
    TranslationMode.patch => '对照文件',
    TranslationMode.online => '在线翻译',
  };
}

enum TranslationProvider {
  openAi,
  anthropic,
  deepL,
  google,
  baidu,
  youdao;

  String get label => switch (this) {
    TranslationProvider.openAi => 'OpenAI',
    TranslationProvider.anthropic => 'Anthropic',
    TranslationProvider.deepL => 'DeepL',
    TranslationProvider.google => 'Google 翻译',
    TranslationProvider.baidu => '百度翻译',
    TranslationProvider.youdao => '有道翻译',
  };

  String get defaultEndpoint => switch (this) {
    TranslationProvider.openAi => 'https://api.openai.com/v1/responses',
    TranslationProvider.anthropic => 'https://api.anthropic.com/v1/messages',
    TranslationProvider.deepL => 'https://api-free.deepl.com/v2/translate',
    TranslationProvider.google =>
      'https://translation.googleapis.com/language/translate/v2',
    TranslationProvider.baidu =>
      'https://fanyi-api.baidu.com/api/trans/vip/translate',
    TranslationProvider.youdao => 'https://openapi.youdao.com/api',
  };

  String get defaultModel => switch (this) {
    TranslationProvider.openAi => 'gpt-4.1-mini',
    TranslationProvider.anthropic => 'claude-sonnet-4-20250514',
    _ => '',
  };

  bool get usesModel =>
      this == TranslationProvider.openAi ||
      this == TranslationProvider.anthropic;

  bool get usesApiKey =>
      this == TranslationProvider.openAi ||
      this == TranslationProvider.anthropic ||
      this == TranslationProvider.deepL ||
      this == TranslationProvider.google;

  bool get usesAppCredentials =>
      this == TranslationProvider.baidu || this == TranslationProvider.youdao;

  bool get endpointEditable =>
      this == TranslationProvider.openAi ||
      this == TranslationProvider.anthropic ||
      this == TranslationProvider.deepL;
}

class TranslationProviderConfig {
  const TranslationProviderConfig({
    required this.endpoint,
    this.apiKey = '',
    this.appId = '',
    this.appSecret = '',
    this.model = '',
  });

  factory TranslationProviderConfig.defaults(TranslationProvider provider) {
    return TranslationProviderConfig(
      endpoint: provider.defaultEndpoint,
      model: provider.defaultModel,
    );
  }

  factory TranslationProviderConfig.fromJson(
    TranslationProvider provider,
    Map<String, dynamic> json,
  ) {
    final defaults = TranslationProviderConfig.defaults(provider);
    return TranslationProviderConfig(
      endpoint: json['endpoint']?.toString() ?? defaults.endpoint,
      apiKey: json['apiKey']?.toString() ?? '',
      appId: json['appId']?.toString() ?? '',
      appSecret: json['appSecret']?.toString() ?? '',
      model: json['model']?.toString() ?? defaults.model,
    );
  }

  factory TranslationProviderConfig.fromSettings(TranslationSettings settings) {
    return TranslationProviderConfig(
      endpoint: settings.endpoint,
      apiKey: settings.apiKey,
      appId: settings.appId,
      appSecret: settings.appSecret,
      model: settings.model,
    );
  }

  final String endpoint;
  final String apiKey;
  final String appId;
  final String appSecret;
  final String model;

  Map<String, dynamic> toJson() => {
    'endpoint': endpoint,
    'apiKey': apiKey,
    'appId': appId,
    'appSecret': appSecret,
    'model': model,
  };
}

class TranslationSettings {
  static const defaultEndpoint = 'https://api.openai.com/v1/responses';
  // Used only while migrating settings written by the first online-translation
  // build, which spoke the Chat Completions protocol.
  static const legacyDefaultEndpoint =
      'https://api.openai.com/v1/chat/completions';
  static const defaultModel = 'gpt-4.1-mini';

  const TranslationSettings({
    this.mode = TranslationMode.off,
    this.patchPath = '',
    this.provider = TranslationProvider.openAi,
    this.endpoint = defaultEndpoint,
    this.apiKey = '',
    this.appId = '',
    this.appSecret = '',
    this.model = defaultModel,
    this.sourceLanguage = '日语',
    this.targetLanguage = '简体中文',
  });

  final TranslationMode mode;
  final String patchPath;
  final TranslationProvider provider;
  final String endpoint;
  final String apiKey;
  final String appId;
  final String appSecret;
  final String model;
  final String sourceLanguage;
  final String targetLanguage;

  TranslationSettings copyWith({
    TranslationMode? mode,
    String? patchPath,
    TranslationProvider? provider,
    String? endpoint,
    String? apiKey,
    String? appId,
    String? appSecret,
    String? model,
    String? sourceLanguage,
    String? targetLanguage,
  }) {
    return TranslationSettings(
      mode: mode ?? this.mode,
      patchPath: patchPath ?? this.patchPath,
      provider: provider ?? this.provider,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
      appId: appId ?? this.appId,
      appSecret: appSecret ?? this.appSecret,
      model: model ?? this.model,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
    );
  }
}
