library wizard_builder;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:wizard_builder/wizard_page.dart';

typedef WizardPageBuilder = WizardPage Function(BuildContext context);

class WizardInherited extends InheritedWidget {
  WizardInherited({Key key}) : super(key: key);

  static WizardInherited of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WizardInherited>();
  }

  @override
  Widget get child => Container();

  @override
  bool updateShouldNotify(WizardInherited oldWidget) {
    return true;
  }

  void onPush(BuildContext context) {
    WizardBuilder.of(context).nextPage();
  }
}

class WizardBuilder extends StatefulWidget {
  WizardBuilder({
    Key key,
    @required this.navigatorKey,
    @required this.pages,
  })  : controller = StreamController(),
        assert(navigatorKey != null),
        assert(pages != null && pages.isNotEmpty),
        super(key: key);

  final GlobalKey<NavigatorState> navigatorKey;
  final List<Widget> pages;
  final ListQueue<_WizardItem> widgetPageStack = ListQueue();

  @override
  WizardBuilderState createState() => WizardBuilderState();

  static WizardBuilderState of(BuildContext context) {
    final WizardBuilderState wizard =
        context.findAncestorStateOfType<WizardBuilderState>();
    assert(() {
      // if (wizard == null) {
      //   throw FlutterError(
      //       'WizardBuilder operation requested with a context that does not include a WizardBuilder.\n'
      //       'The context used to push or pop routes from the WizardBuilder must be that of a '
      //       'widget that is a descendant of a WizardBuilder widget.');
      // }
      return true;
    }());
    return wizard;
  }

  final StreamController controller;
}

class WizardBuilderState<T extends StatefulWidget> extends State<WizardBuilder>
    with RouteAware {
  List<_WizardItem> _fullPageStack = List<_WizardItem>();
  ListQueue<_WizardItem> _currentPageStack = ListQueue();

  _WizardItem get currentItem =>
      (widget.widgetPageStack.length > 0) ? widget.widgetPageStack.last : null;

  Widget get currentPage =>
      (currentItem != null) ? currentItem.widget(context) : null;

  final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

  @override
  void initState() {
    _fullPageStack = _WizardItem.flattenPages(widget.pages);

    widget.widgetPageStack.clear();
    widget.widgetPageStack.addLast(_fullPageStack[0]);
    _currentPageStack = widget.widgetPageStack;

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    _fullPageStack = _WizardItem.flattenPages(widget.pages);
    _currentPageStack = widget.widgetPageStack;
    return WillPopScope(
      onWillPop: () {
        var currentPage = _currentPageStack.last.widget(context);
        if (currentPage is WizardBuilder) {
          if (currentPage.widgetPageStack.length > 1) {
            currentPage.navigatorKey.currentState.pop();
            return Future.value(false);
          }

          widget.navigatorKey.currentState.pop();
          return Future.value(false);
        }

        if (currentPage is WizardPage) {
          widget.navigatorKey.currentState.pop();
          return Future.value(false);
        }

        return Future.value(true);
      },
      child: Navigator(
        key: widget.navigatorKey,
        observers: [routeObserver],
        initialRoute: _fullPageStack.first.route,
        onGenerateRoute: (routeSettings) {
          return initialRoute();
        },
      ),
    );
  }

  initialRoute() {
    return MaterialPageRoute(
      builder: (context) => _fullPageStack[0].widget(context),
      settings: RouteSettings(name: '/'),
    );
  }

  Future<bool> nextPage() async {
    _fullPageStack = _WizardItem.flattenPages(widget.pages);
    _currentPageStack = widget.widgetPageStack;
    if (_isLastPage()) {
      closeWizard();
      return true;
    }

    var currentPageIndex =
        _fullPageStack.indexWhere((p) => p.index == currentItem?.index);

    currentPageIndex = currentPageIndex == -1 ? 0 : currentPageIndex;

    widget.widgetPageStack.addLast(_fullPageStack[currentPageIndex + 1]);
    _currentPageStack = widget.widgetPageStack;

    _WizardItem nextPage = _fullPageStack[currentPageIndex + 1];

    await _pushItem(context, nextPage);

    widget.widgetPageStack.removeLast();
    _currentPageStack = widget.widgetPageStack;

    var currentPage = widget.widgetPageStack.last.widget(context);
    if (currentPage is WizardBuilder) {
      var lastPage = currentPage.pages.cast<WizardPage>().last;
      if (lastPage.closeOnNavigate) {
        currentPage.navigatorKey.currentState.pop();
      }
    }

    if (currentPage is WizardPage) {
      if (currentPage.closeOnNavigate) {
        closePage();
      }
    }

    return true;
  }

  void closePage() {
    _pop(context);
  }

  Future closeWizard() async {
    _fullPageStack = _WizardItem.flattenPages(widget.pages);
    _currentPageStack = widget.widgetPageStack;
    var parentWizard = WizardBuilder.of(context);
    if (parentWizard != null) {
      await parentWizard.nextPage();
      return;
    }

    //reached the end of the wizard and close it all
    var rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.pop();
    } else {
      throw FlutterError(
          'The Wizard cannot be closed, because there is no root navigator. Please start the Wizard from a.\n'
          'root navigator.');
    }
  }

  bool _isLastPage() {
    return widget.widgetPageStack.length == _fullPageStack.length;
  }

  Future _pushItem(BuildContext context, _WizardItem item,
      {bool isModal = false}) {
    return widget.navigatorKey.currentState.push(
      MaterialPageRoute(
        builder: (context) => item.widget(context),
        settings: RouteSettings(name: item.route),
        fullscreenDialog: isModal,
      ),
    );
  }

  void _pop(BuildContext context) {
    Navigator.of(context).pop();
  }
}

class _WizardItem {
  final int index;
  final WidgetBuilder widget;
  final WizardPage page;
  final String route;
  final bool isModal;

  static List<_WizardItem> pageStack = List<_WizardItem>();

  _WizardItem(
      {this.index, this.widget, this.page, this.route, this.isModal = false});

  static List<_WizardItem> flattenPages(List<Widget> pages) {
    pageStack.clear();

    for (var i = 0; i < pages.length; i++) {
      //add initial route as '/'
      WizardPage wizPage = pages[i];
      String route = (i == 0) ? '/' : '/${UniqueKey().toString()}';

      pageStack.add(
        _WizardItem(
            index: i,
            widget: (context) => wizPage,
            page: wizPage,
            route: route,
            isModal: wizPage.isModal),
      );
    }

    return pageStack;
  }

  @override
  String toString() {
    return '$index -> $route : ${page.toString()}';
  }
}
