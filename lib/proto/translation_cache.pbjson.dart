// This is a generated file - do not edit.
//
// Generated from translation_cache.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use translationCacheDescriptor instead')
const TranslationCache$json = {
  '1': 'TranslationCache',
  '2': [
    {
      '1': 'entries',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.art3m1s.translation.TranslationCache.EntriesEntry',
      '10': 'entries'
    },
  ],
  '3': [TranslationCache_EntriesEntry$json],
};

@$core.Deprecated('Use translationCacheDescriptor instead')
const TranslationCache_EntriesEntry$json = {
  '1': 'EntriesEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `TranslationCache`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List translationCacheDescriptor = $convert.base64Decode(
    'ChBUcmFuc2xhdGlvbkNhY2hlEkwKB2VudHJpZXMYASADKAsyMi5hcnQzbTFzLnRyYW5zbGF0aW'
    '9uLlRyYW5zbGF0aW9uQ2FjaGUuRW50cmllc0VudHJ5UgdlbnRyaWVzGjoKDEVudHJpZXNFbnRy'
    'eRIQCgNrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWU6AjgB');
