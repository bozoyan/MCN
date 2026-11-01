// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// TodoDao Provider

@ProviderFor(todoDao)
final todoDaoProvider = TodoDaoProvider._();

/// TodoDao Provider

final class TodoDaoProvider
    extends $FunctionalProvider<AsyncValue<TodoDao>, TodoDao, FutureOr<TodoDao>>
    with $FutureModifier<TodoDao>, $FutureProvider<TodoDao> {
  /// TodoDao Provider
  TodoDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todoDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todoDaoHash();

  @$internal
  @override
  $FutureProviderElement<TodoDao> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<TodoDao> create(Ref ref) {
    return todoDao(ref);
  }
}

String _$todoDaoHash() => r'657e81ebc25fe9801455434ea2a1867a56913182';

/// 当前会话的 Todo 列表 Provider（含增删改操作）

@ProviderFor(SessionTodos)
final sessionTodosProvider = SessionTodosFamily._();

/// 当前会话的 Todo 列表 Provider（含增删改操作）
final class SessionTodosProvider
    extends $AsyncNotifierProvider<SessionTodos, List<Todo>> {
  /// 当前会话的 Todo 列表 Provider（含增删改操作）
  SessionTodosProvider._({
    required SessionTodosFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'sessionTodosProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$sessionTodosHash();

  @override
  String toString() {
    return r'sessionTodosProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SessionTodos create() => SessionTodos();

  @override
  bool operator ==(Object other) {
    return other is SessionTodosProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$sessionTodosHash() => r'fda298a5dafb75b861d174ff77dc6840aab67a9b';

/// 当前会话的 Todo 列表 Provider（含增删改操作）

final class SessionTodosFamily extends $Family
    with
        $ClassFamilyOverride<
          SessionTodos,
          AsyncValue<List<Todo>>,
          List<Todo>,
          FutureOr<List<Todo>>,
          String?
        > {
  SessionTodosFamily._()
    : super(
        retry: null,
        name: r'sessionTodosProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 当前会话的 Todo 列表 Provider（含增删改操作）

  SessionTodosProvider call(String? sessionId) =>
      SessionTodosProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'sessionTodosProvider';
}

/// 当前会话的 Todo 列表 Provider（含增删改操作）

abstract class _$SessionTodos extends $AsyncNotifier<List<Todo>> {
  late final _$args = ref.$arg as String?;
  String? get sessionId => _$args;

  FutureOr<List<Todo>> build(String? sessionId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Todo>>, List<Todo>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Todo>>, List<Todo>>,
              AsyncValue<List<Todo>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// 当前待处理任务数量

@ProviderFor(pendingTodoCount)
final pendingTodoCountProvider = PendingTodoCountFamily._();

/// 当前待处理任务数量

final class PendingTodoCountProvider extends $FunctionalProvider<int, int, int>
    with $Provider<int> {
  /// 当前待处理任务数量
  PendingTodoCountProvider._({
    required PendingTodoCountFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'pendingTodoCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pendingTodoCountHash();

  @override
  String toString() {
    return r'pendingTodoCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<int> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int create(Ref ref) {
    final argument = this.argument as String?;
    return pendingTodoCount(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PendingTodoCountProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pendingTodoCountHash() => r'6d7dd08b186193a0ad60dbdcbe5cc77eed53e210';

/// 当前待处理任务数量

final class PendingTodoCountFamily extends $Family
    with $FunctionalFamilyOverride<int, String?> {
  PendingTodoCountFamily._()
    : super(
        retry: null,
        name: r'pendingTodoCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 当前待处理任务数量

  PendingTodoCountProvider call(String? sessionId) =>
      PendingTodoCountProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'pendingTodoCountProvider';
}

/// 当前进行中任务

@ProviderFor(currentInProgressTodo)
final currentInProgressTodoProvider = CurrentInProgressTodoFamily._();

/// 当前进行中任务

final class CurrentInProgressTodoProvider
    extends $FunctionalProvider<Todo?, Todo?, Todo?>
    with $Provider<Todo?> {
  /// 当前进行中任务
  CurrentInProgressTodoProvider._({
    required CurrentInProgressTodoFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'currentInProgressTodoProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$currentInProgressTodoHash();

  @override
  String toString() {
    return r'currentInProgressTodoProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Todo?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Todo? create(Ref ref) {
    final argument = this.argument as String?;
    return currentInProgressTodo(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Todo? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Todo?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CurrentInProgressTodoProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$currentInProgressTodoHash() =>
    r'a0fa327df9f2d0d5ed2b8bed611d48c8af16d738';

/// 当前进行中任务

final class CurrentInProgressTodoFamily extends $Family
    with $FunctionalFamilyOverride<Todo?, String?> {
  CurrentInProgressTodoFamily._()
    : super(
        retry: null,
        name: r'currentInProgressTodoProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 当前进行中任务

  CurrentInProgressTodoProvider call(String? sessionId) =>
      CurrentInProgressTodoProvider._(argument: sessionId, from: this);

  @override
  String toString() => r'currentInProgressTodoProvider';
}
