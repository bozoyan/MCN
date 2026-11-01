// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agent_rule_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// AgentRule 实时流

@ProviderFor(agentRulesStream)
final agentRulesStreamProvider = AgentRulesStreamFamily._();

/// AgentRule 实时流

final class AgentRulesStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentRule>>,
          List<AgentRule>,
          Stream<List<AgentRule>>
        >
    with $FutureModifier<List<AgentRule>>, $StreamProvider<List<AgentRule>> {
  /// AgentRule 实时流
  AgentRulesStreamProvider._({
    required AgentRulesStreamFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'agentRulesStreamProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentRulesStreamHash();

  @override
  String toString() {
    return r'agentRulesStreamProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<AgentRule>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<AgentRule>> create(Ref ref) {
    final argument = this.argument as String;
    return agentRulesStream(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentRulesStreamProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentRulesStreamHash() => r'5f0e9f01de21772b64e6d1f5202e509ba1ca35c7';

/// AgentRule 实时流

final class AgentRulesStreamFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<AgentRule>>, String> {
  AgentRulesStreamFamily._()
    : super(
        retry: null,
        name: r'agentRulesStreamProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// AgentRule 实时流

  AgentRulesStreamProvider call(String databasePath) =>
      AgentRulesStreamProvider._(argument: databasePath, from: this);

  @override
  String toString() => r'agentRulesStreamProvider';
}
