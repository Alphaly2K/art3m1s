// This is a generated file - do not edit.
//
// Generated from translation_cache.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class TranslationCache extends $pb.GeneratedMessage {
  factory TranslationCache({
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? entries,
  }) {
    final result = create();
    if (entries != null) result.entries.addEntries(entries);
    return result;
  }

  TranslationCache._();

  factory TranslationCache.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TranslationCache.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TranslationCache',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'art3m1s.translation'),
      createEmptyInstance: create)
    ..m<$core.String, $core.String>(1, _omitFieldNames ? '' : 'entries',
        entryClassName: 'TranslationCache.EntriesEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('art3m1s.translation'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranslationCache clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TranslationCache copyWith(void Function(TranslationCache) updates) =>
      super.copyWith((message) => updates(message as TranslationCache))
          as TranslationCache;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TranslationCache create() => TranslationCache._();
  @$core.override
  TranslationCache createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TranslationCache getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TranslationCache>(create);
  static TranslationCache? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbMap<$core.String, $core.String> get entries => $_getMap(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
