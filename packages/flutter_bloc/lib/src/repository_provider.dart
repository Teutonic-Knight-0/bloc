import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nested/nested.dart';

typedef Create<T> = T Function(BuildContext);

/// Mixin which allows `MultiRepositoryProvider` to infer the types
/// of multiple [RepositoryProvider]s.
mixin RepositoryProviderSingleChildWidget on SingleChildWidget {}

/// {@template repository_provider}
/// Takes a `ValueBuilder` that is responsible for creating the repository and
/// a `child` which will have access to the repository via
/// `RepositoryProvider.of(context)`.
/// It is used as a dependency injection (DI) widget so that a single instance
/// of a repository can be provided to multiple widgets within a subtree.
///
/// Lazily creates the provided repository unless `lazy` is set to `false`.
///
/// ```dart
/// RepositoryProvider(
///   create: (context) => RepositoryA(),
///   child: ChildA(),
/// );
/// ```
/// {@endtemplate}
class RepositoryProvider<T> extends SingleChildStatefulWidget
    with RepositoryProviderSingleChildWidget {
  /// {@macro repository_provider}
  RepositoryProvider({
    Key key,
    @required this.create,
    this.child,
    this.lazy = true,
  }) : super(key: key);

  /// Takes a repository and a [child] which will have access to the repository.
  /// A new repository should not be created in `RepositoryProvider.value`.
  /// Repositories should always be created using the default constructor
  /// within the `builder`.
  RepositoryProvider.value({
    Key key,
    @required T value,
    Widget child,
  }) : this(
          key: key,
          create: (_) => value,
          child: child,
        );

  /// Creates the repository of type [T].
  final Create<T> create;

  /// Widget which will have access to the repository.
  final Widget child;

  /// Whether the repository should be created lazily.
  /// Defaults to `true`.
  final bool lazy;

  /// Method that allows widgets to access a repository instance as long as
  /// their `BuildContext` contains a [RepositoryProvider] instance.
  static T of<T>(BuildContext context) {
    final provider = context
        .getElementForInheritedWidgetOfExactType<_InheritedRepository<T>>()
        ?.widget as _InheritedRepository<T>;
    if (provider == null) {
      throw FlutterError(
        '''
        RepositoryProvider.of() called with a context that does not contain a repository of type $T.
        No ancestor could be found starting from the context that was passed to RepositoryProvider.of<$T>().

        This can happen if the context you used comes from a widget above the RepositoryProvider.

        The context used was: $context
        ''',
      );
    }
    return provider.create();
  }

  @override
  _RepositoryProviderState<T> createState() => _RepositoryProviderState<T>();
}

class _RepositoryProviderState<T>
    extends SingleChildState<RepositoryProvider<T>> {
  T _repository;
  final _completer = Completer<T>();

  @override
  void initState() {
    super.initState();
    if (!widget.lazy) {
      _repository = widget.create(context);
      _completer.complete(_repository);
    }
  }

  @override
  Widget buildWithChild(BuildContext context, Widget child) {
    return _InheritedRepository(
      create: () {
        if (!_completer.isCompleted) {
          _repository = widget.create(context);
          _completer.complete(_repository);
        }
        return _repository;
      },
      deferredRepository: _completer.future,
      child: child ?? widget.child,
    );
  }
}

/// Extends the `BuildContext` class with the ability
/// to perform a lookup based on a repository type.
extension RepositoryProviderExtension on BuildContext {
  /// Performs a lookup using the `BuildContext` to obtain
  /// the nearest ancestor repository of type [T].
  ///
  /// Calling this method is equivalent to calling:
  ///
  /// ```dart
  /// RepositoryProvider.of<T>(context)
  /// ```
  T repository<T>() => RepositoryProvider.of<T>(this);
}

class _InheritedRepository<T> extends InheritedWidget {
  const _InheritedRepository({
    Key key,
    this.deferredRepository,
    this.create,
    @required Widget child,
  })  : assert(child != null),
        super(key: key, child: child);

  final Future<T> deferredRepository;
  final T Function() create;

  @override
  bool updateShouldNotify(_InheritedRepository<T> oldWidget) {
    return oldWidget.deferredRepository != deferredRepository;
  }

  @override
  _InheritedRepositoryElement<T> createElement() =>
      _InheritedRepositoryElement<T>(this);
}

class _InheritedRepositoryElement<T> extends InheritedElement {
  _InheritedRepositoryElement(
    _InheritedRepository<T> widget,
  ) : super(widget) {
    widget.deferredRepository?.then((repository) {
      _handleUpdate();
    });
  }

  @override
  _InheritedRepository<T> get widget => super.widget as _InheritedRepository<T>;

  bool _dirty = false;

  @override
  void update(_InheritedRepository<T> newWidget) {
    final oldRepository = widget.deferredRepository;
    final newRepository = newWidget.deferredRepository;
    if (oldRepository != newRepository) {
      newRepository?.then((repository) {
        _handleUpdate();
      });
    }
    super.update(newWidget);
  }

  @override
  Widget build() {
    if (_dirty) notifyClients(widget);
    return super.build();
  }

  void _handleUpdate() {
    _dirty = true;
    markNeedsBuild();
  }

  @override
  void notifyClients(_InheritedRepository<T> oldWidget) {
    super.notifyClients(oldWidget);
    _dirty = false;
  }

  @override
  void unmount() {
    super.unmount();
  }
}
