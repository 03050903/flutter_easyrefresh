import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'header/header.dart';
import 'footer/footer.dart';
import 'behavior/behavior.dart';

typedef Future OnRefresh();
typedef Future LoadMore();
typedef ScrollPhysicsChanged(ScrollPhysics physics);
typedef AnimationStateChanged(AnimationStates animationStates, RefreshBoxDirectionStatus refreshBoxDirectionStatus);

enum RefreshBoxDirectionStatus {
  //  上拉加载的状态 分别为 闲置 上拉  下拉
  IDLE,
  PUSH,
  PULL
}

enum AnimationStates {
  // 未达到刷新高度
  DragAndRefreshNotEnabled,
  // 达到刷新高度
  DragAndRefreshEnabled,
  // 开始加载
  StartLoadData,
  // 加载完成
  LoadDataEnd,
  // 视图消失
  RefreshBoxIdle
}

class EasyRefresh extends StatefulWidget {
  final OnRefresh onRefresh;
  final LoadMore loadMore;
  final ScrollPhysicsChanged scrollPhysicsChanged;
  final ScrollView child;
  // 滚动视图光晕
  final ScrollBehavior behavior;
  // 顶部和底部视图
  final RefreshHeader refreshHeader;
  final RefreshFooter refreshFooter;
  // 状态改变回调
  final AnimationStateChanged animationStateChangedCallback;
  // 自动加载(滑动到底部时)
  final bool autoLoad;

  EasyRefresh({
    @required this.scrollPhysicsChanged,
    GlobalKey<EasyRefreshState> key,
    this.behavior,
    this.refreshHeader,
    this.refreshFooter,
    this.animationStateChangedCallback,
    this.onRefresh,
    this.loadMore,
    this.autoLoad: false,
    @required this.child
  }) : super(key: key) {
    assert(child != null);
  }

  // 获取键
  GlobalKey<EasyRefreshState> getKey() {
    return this.key;
  }

  @override
  EasyRefreshState createState() {
    return new EasyRefreshState();
  }
}

class EasyRefreshState extends State<EasyRefresh> with TickerProviderStateMixin<EasyRefresh> {
  // 顶部栏和底部栏高度
  double _topItemHeight = 0.0;
  double _bottomItemHeight = 0.0;
  // 动画控制
  Animation<double> _animation;
  AnimationController _animationController;
  AnimationController _animationControllerWait;
  double _shrinkageDistance = 0.0;
  // 出发刷新和加载的高度
  double _refreshHeight = 50.0;
  double _loadHeight = 50.0;
  // 刷新和加载的状态
  RefreshBoxDirectionStatus _states = RefreshBoxDirectionStatus.IDLE;
  RefreshBoxDirectionStatus _lastStates = RefreshBoxDirectionStatus.IDLE;
  AnimationStates _animationStates = AnimationStates.RefreshBoxIdle;
  // 刷新的状态记录
  bool _isReset = false;
  bool _isPulling = false;
  bool _isPushing = false;
  // 记录子类条目(触发刷新和加载时记录)
  int _itemCount = 0;

  // 顶部视图
  RefreshHeader _refreshHeader;

  // 底部视图
  RefreshFooter _refreshFooter;

  // 触发刷新
  void callRefresh() {
    setState(() {
      _topItemHeight = _refreshHeight + 20.0;
    });
    // 等待列表高度渲染完成
    new Future.delayed(const Duration(milliseconds: 200), () async {
      widget.scrollPhysicsChanged(new NeverScrollableScrollPhysics());
      _animationController.forward();
    });
  }

  // 触发加载
  void callLoadMore() async {
    if (_isPushing) return;
    _isPushing = true;
    setState(() {
      _bottomItemHeight = _loadHeight + 20.0;
    });
    // 等待列表高度渲染完成
    new Future.delayed(const Duration(milliseconds: 200), () async {
      widget.scrollPhysicsChanged(new NeverScrollableScrollPhysics());
      _animationController.forward();
    });
    //widget.child.controller.animateTo(widget.child.controller.position.maxScrollExtent, duration: new Duration(milliseconds: 500), curve: Curves.ease);
  }

  @override
  void initState() {
    super.initState();
    // 初始化刷新高度
    _refreshHeight = widget.refreshHeader == null ? 50.0 : widget.refreshHeader.refreshHeight;
    _loadHeight = widget.refreshFooter == null ? 50.0 : widget.refreshFooter.loadHeight;
    // 这个是刷新时控件旋转的动画，用来使刷新的Icon动起来
    _animationControllerWait = new AnimationController(
        duration: const Duration(milliseconds: 1000 * 100), vsync: this);
    _animationController = new AnimationController(
        duration: const Duration(milliseconds: 250), vsync: this);
    _animation = new Tween(begin: 1.0, end: 0.0).animate(_animationController)
      ..addListener(() {
        //因为_animationController reset()后，addListener会收到监听，导致再执行一遍setState _topItemHeight和_bottomItemHeight会异常 所以用此标记
        //判断是reset的话就返回避免异常
        if (_isReset) {
          return;
        }
        //根据动画的值逐渐减小布局的高度，分为4种情况
        // 1.上拉高度超过_refreshHeight    2.上拉高度不够50   3.下拉拉高度超过_refreshHeight  4.下拉拉高度不够50
        setState(() {
          if (_topItemHeight > _refreshHeight) {
            //_shrinkageDistance*animation.value是由大变小的，模拟出弹回的效果
            _topItemHeight = _refreshHeight + _shrinkageDistance * _animation.value;
          } else if (_bottomItemHeight > _loadHeight) {
            _bottomItemHeight = _loadHeight + _shrinkageDistance * _animation.value;
            //高度小于50时↓
          } else if (_topItemHeight <= _refreshHeight && _topItemHeight > 0) {
            _topItemHeight = _shrinkageDistance * _animation.value;
          } else if (_bottomItemHeight <= _loadHeight && _bottomItemHeight > 0) {
            _bottomItemHeight = _shrinkageDistance * _animation.value;
          }
        });
      });

    _animation.addStatusListener((animationStatus) {
      if (animationStatus == AnimationStatus.completed) {
        //动画结束时首先将_animationController重置
        _isReset = true;
        _animationController.reset();
        _isReset = false;
        //动画完成后只有2种情况，高度是50和0，如果是高度》=50的，则开始刷新或者加载操作，如果是0则恢复ListView
        setState(() {
          if (_topItemHeight >= _refreshHeight) {
            _topItemHeight = _refreshHeight;
            _refreshStart(RefreshBoxDirectionStatus.PULL);
          } else if (_bottomItemHeight >= _loadHeight) {
            _bottomItemHeight = _loadHeight;
            _refreshStart(RefreshBoxDirectionStatus.PUSH);
            //动画结束，高度回到0，上下拉刷新彻底结束，ListView恢复正常
          } else if (_states == RefreshBoxDirectionStatus.PUSH) {
            _topItemHeight = 0.0;
            widget.scrollPhysicsChanged(new RefreshAlwaysScrollPhysics());
            _states = RefreshBoxDirectionStatus.IDLE;
            _checkStateAndCallback(AnimationStates.RefreshBoxIdle, RefreshBoxDirectionStatus.IDLE);
          } else if (_states == RefreshBoxDirectionStatus.PULL) {
            _bottomItemHeight = 0.0;
            widget.scrollPhysicsChanged(new RefreshAlwaysScrollPhysics());
            _states = RefreshBoxDirectionStatus.IDLE;
            _isPulling = false;
            _checkStateAndCallback(AnimationStates.RefreshBoxIdle, RefreshBoxDirectionStatus.IDLE);
          }
        });
      } else if (animationStatus == AnimationStatus.forward) {
        //动画开始时根据情况计算要弹回去的距离
        if (_topItemHeight > _refreshHeight) {
          _shrinkageDistance = _topItemHeight - _refreshHeight;
        } else if (_bottomItemHeight > _loadHeight) {
          _shrinkageDistance = _bottomItemHeight - _loadHeight;
          //这里必须有个动画，不然上拉加载时  ListView不会自动滑下去，导致ListView悬在半空
          widget.child.controller.animateTo(
              widget.child.controller.position.maxScrollExtent,
              duration: new Duration(milliseconds: 250),
              curve: Curves.linear);
        } else if (_topItemHeight <= _refreshHeight && _topItemHeight > 0.0) {
          _shrinkageDistance = _topItemHeight;
          _states = RefreshBoxDirectionStatus.PUSH;
        } else if (_bottomItemHeight <= _loadHeight && _bottomItemHeight > 0.0) {
          _shrinkageDistance = _bottomItemHeight;
          _states = RefreshBoxDirectionStatus.PULL;
        }
      }
    });
  }

  // 生成底部栏
  Widget _getFooter() {
    if (widget.loadMore != null) {
      if (this._refreshFooter != null) return this._refreshFooter;
      if (widget.refreshFooter == null) {
        this._refreshFooter = __classicsFooterBuilder();
      } else {
        this._refreshFooter = widget.refreshFooter;
      }
      return this._refreshFooter;
    } else {
      return new Container();
    }
  }

  // 默认底部栏
  Widget __classicsFooterBuilder() {
    return new ClassicsFooter();
  }

  // 生成顶部栏
  Widget _getHeader() {
    if (widget.onRefresh != null) {
      if (this._refreshHeader != null) return this._refreshHeader;
      if (widget.refreshHeader == null) {
        this._refreshHeader = _classicsHeaderBuilder();
      } else {
        this._refreshHeader = widget.refreshHeader;
      }
      return this._refreshHeader;
    } else {
      return new Container();
    }
  }

  // 默认顶部栏
  Widget _classicsHeaderBuilder() {
    return ClassicsHeader();
  }

  void _refreshStart(RefreshBoxDirectionStatus refreshBoxDirectionStatus) async {
    _checkStateAndCallback(AnimationStates.StartLoadData, refreshBoxDirectionStatus);
    if (refreshBoxDirectionStatus == RefreshBoxDirectionStatus.PULL &&
        this._refreshHeader == null &&
        widget.onRefresh != null) {
      //开始加载等待的动画
      _animationControllerWait.forward();
    } else if (refreshBoxDirectionStatus == RefreshBoxDirectionStatus.PUSH &&
        this._refreshFooter == null &&
        widget.loadMore != null) {
      //开始加载等待的动画
      _animationControllerWait.forward();
    }

    // 这里我们开始加载数据 数据加载完成后，将新数据处理并开始加载完成后的处理
    if (_topItemHeight > _bottomItemHeight) {
      if (widget.onRefresh != null) {
        // 调用刷新回调
        await widget.onRefresh();
      }
    } else {
      if (widget.loadMore != null) {
        // 调用加载更多
        await widget.loadMore();
        // 稍作延时(等待列表加载完成,用于判断前后条数差异)
        await new Future.delayed(const Duration(milliseconds: 200), () {});
      }
    }
    if (!mounted) return;

    if (_animationControllerWait.isAnimating) {
      // 结束加载等待的动画
      _animationControllerWait.stop();
    }
    _checkStateAndCallback(AnimationStates.LoadDataEnd, refreshBoxDirectionStatus);
    await Future.delayed(new Duration(seconds: 1));
    // 开始将加载（刷新）布局缩回去的动画
    _animationController.forward();

    if (refreshBoxDirectionStatus == RefreshBoxDirectionStatus.PULL &&
        this._refreshHeader == null &&
        widget.onRefresh != null) {
      // 结束加载等待的动画
      _animationControllerWait.reset();
    } else if (refreshBoxDirectionStatus == RefreshBoxDirectionStatus.PUSH &&
        this._refreshFooter == null &&
        widget.loadMore != null) {
      // 结束加载等待的动画
      _animationControllerWait.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _animationControllerWait.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 更新高度
    if (this._refreshHeader != null) {
      this._refreshHeader.getKey().currentState.updateHeight(_topItemHeight);
    }
    if (this._refreshFooter != null) {
      this._refreshFooter.getKey().currentState.updateHeight(_bottomItemHeight);
    }
    return new Container(
      child: new Column(
        children: <Widget>[
          _getHeader(),
          new Expanded(
            flex: 1,
            child: new NotificationListener(
              onNotification: (ScrollNotification notification) {
                ScrollMetrics metrics = notification.metrics;
                if (notification is ScrollUpdateNotification) {
                  _handleScrollUpdateNotification(notification);
                } else if (notification is ScrollEndNotification) {
                  _handleScrollEndNotification();
                } else if (notification is UserScrollNotification) {
                  _handleUserScrollNotification(notification);
                } else if (metrics.atEdge && notification is OverscrollNotification) {
                  _handleOverScrollNotification(notification);
                }
                return true;
              },
              child: ScrollConfiguration(
                behavior: widget.behavior ?? new RefreshBehavior(),
                child: widget.child,
              ),
            ),
          ),
          _getFooter(),
        ],
      ),
    );
  }

  void _handleScrollUpdateNotification(ScrollUpdateNotification notification) {
    // 判断是否正在加载
    if (_isPushing) return;
    //此处同上
    if (notification.dragDetails == null) {
      return;
    }
    // Header刷新的布局可见时，且当手指反方向拖动（由下向上），notification 为 ScrollUpdateNotification，这个时候让头部刷新布局的高度+delta.dy(此时dy为负数)
    // 来缩小头部刷新布局的高度，当完全看不见时，将scrollPhysics设置为RefreshAlwaysScrollPhysics，来保持ListView的正常滑动
    if (_topItemHeight > 0.0) {
      setState(() {
        //  如果头部的布局高度<0时，将_topItemHeight=0；并恢复ListView的滑动
        if (_topItemHeight + notification.dragDetails.delta.dy / 2 <= 0.0) {
          _checkStateAndCallback(
              AnimationStates.RefreshBoxIdle, RefreshBoxDirectionStatus.IDLE);
          _topItemHeight = 0.0;
          widget.scrollPhysicsChanged(new RefreshAlwaysScrollPhysics());
        } else {
          // 当刷新布局可见时，让头部刷新布局的高度+delta.dy(此时dy为负数)，来缩小头部刷新布局的高度
          _topItemHeight = _topItemHeight + notification.dragDetails.delta.dy / 2;
        }
        // 如果小于刷新高度则恢复下拉刷新
        if (_topItemHeight < _refreshHeight) {
          _checkStateAndCallback(AnimationStates.DragAndRefreshNotEnabled, RefreshBoxDirectionStatus.PULL);
        }
      });
    } else if (_bottomItemHeight > 0.0) {
      // 底部的布局可见时 ，且手指反方向拖动（由上向下），这时notification 为 ScrollUpdateNotification，这个时候让底部加载布局的高度-delta.dy(此时dy为正数数)
      // 来缩小底部加载布局的高度，当完全看不见时，将scrollPhysics设置为RefreshAlwaysScrollPhysics，来保持ListView的正常滑动

      // 当上拉加载时，不知道什么原因，dragDetails可能会为空，导致抛出异常，会发生很明显的卡顿，所以这里必须判空
      if (notification.dragDetails == null) {
        return;
      }
      setState(() {
        //如果底部的布局高度<0时，_bottomItemHeight=0；并恢复ListView的滑动
        if (_bottomItemHeight - notification.dragDetails.delta.dy / 2 <= 0.0) {
          _checkStateAndCallback(AnimationStates.RefreshBoxIdle, RefreshBoxDirectionStatus.IDLE);
          _bottomItemHeight = 0.0;
          widget.scrollPhysicsChanged(new RefreshAlwaysScrollPhysics());
        } else {
          if (notification.dragDetails.delta.dy > 0) {
            //当加载的布局可见时，让上拉加载布局的高度-delta.dy(此时dy为正数数)，来缩小底部的加载布局的高度
            _bottomItemHeight = _bottomItemHeight - notification.dragDetails.delta.dy / 2;
          }
        }
        // 如果小于加载高度则恢复加载
        if (_bottomItemHeight < _loadHeight) {
          _checkStateAndCallback(AnimationStates.DragAndRefreshNotEnabled, RefreshBoxDirectionStatus.PUSH);
        }
      });
    }
  }

  void _handleScrollEndNotification() {
    // 判断是否正在加载
    if (_isPushing) return;
    // 如果滑动结束后（手指抬起来后），判断是否需要启动加载或者刷新的动画
    if ((_topItemHeight > 0 || _bottomItemHeight > 0)) {
      if (_isPulling) {
        return;
      }
      // 这里在动画开始时，做一个标记，表示上拉加载正在进行，因为在超出底部和头部刷新布局的高度后，高度会自动弹回，ListView也会跟着运动，
      // 返回结束时，ListView的运动也跟着结束，会触发ScrollEndNotification，导致再次启动动画，而发生BUG
      if (_bottomItemHeight > 0) {
        _isPulling = true;
      }
      // 启动动画后，ListView不可滑动
      widget.scrollPhysicsChanged(new NeverScrollableScrollPhysics());
      _animationController.forward();
    }
  }

  void _handleUserScrollNotification(UserScrollNotification notification) {
    // 判断是否正在加载
    if (_isPushing) return;
    if (_bottomItemHeight > 0.0 &&
        notification.direction == ScrollDirection.forward) {
      // 底部加载布局出现反向滑动时（由上向下），将scrollPhysics置为RefreshScrollPhysics，只要有2个原因。1 减缓滑回去的速度，2 防止手指快速滑动时出现惯性滑动
      widget.scrollPhysicsChanged(new RefreshScrollPhysics());
    } else if (_topItemHeight > 0.0 &&
        notification.direction == ScrollDirection.reverse) {
      // 头部刷新布局出现反向滑动时（由下向上）
      widget.scrollPhysicsChanged(new RefreshScrollPhysics());
    } else if (_bottomItemHeight > 0.0 &&
        notification.direction == ScrollDirection.reverse) {
      // 反向再反向（恢复正向拖动）
      widget.scrollPhysicsChanged(new RefreshAlwaysScrollPhysics());
    }
  }

  void _handleOverScrollNotification(OverscrollNotification notification) {
    // 判断是否正在加载
    if (_isPushing) return;
    //OverScrollNotification 和 metrics.atEdge 说明正在下拉或者 上拉
    // 此处同上
    if (notification.dragDetails == null) {
      return;
    }
    // 如果notification.overScroll<0.0 说明是在下拉刷新，这里根据拉的距离设定高度的增加范围-->刷新高度时  是拖动速度的1/2，高度在刷新高度及大于40时 是
    // 拖动速度的1/4  .........若果超过100+刷新高度，结束拖动，自动开始刷新，拖过刷新布局高度小于0，恢复ListView的正常拖动
    // 当Item的数量不能铺满全屏时  上拉加载会引起下拉布局的出现，所以这里要判断下_bottomItemHeight<0.5
    if (notification.overscroll < 0.0 && _bottomItemHeight < 0.5 && widget.onRefresh != null) {
      setState(() {
        if (notification.dragDetails.delta.dy / 2 + _topItemHeight <= 0.0) {
          // Refresh回弹完毕，恢复正常ListView的滑动状态
          _checkStateAndCallback(AnimationStates.RefreshBoxIdle, RefreshBoxDirectionStatus.IDLE);
          _topItemHeight = 0.0;
          widget.scrollPhysicsChanged(new RefreshAlwaysScrollPhysics());
        } else {
          if (_topItemHeight > 100.0 + _refreshHeight) {
            widget.scrollPhysicsChanged(new NeverScrollableScrollPhysics());
            _animationController.forward();
          } else if (_topItemHeight > 40.0 + _refreshHeight) {
            _topItemHeight = notification.dragDetails.delta.dy / 6 + _topItemHeight;
          } else if (_topItemHeight > _refreshHeight) {
            _checkStateAndCallback(AnimationStates.DragAndRefreshEnabled, RefreshBoxDirectionStatus.PULL);
            _topItemHeight = notification.dragDetails.delta.dy / 4 + _topItemHeight;
          } else {
            _checkStateAndCallback(AnimationStates.DragAndRefreshNotEnabled, RefreshBoxDirectionStatus.PULL);
            _topItemHeight = notification.dragDetails.delta.dy / 2 + _topItemHeight;
          }
        }
      });
    } else if (_topItemHeight < 0.5 && widget.loadMore != null) {
      // 判断是否滑动到底部并自动加载
      if (widget.autoLoad) {
        callLoadMore();
      }
      setState(() {
        if (-notification.dragDetails.delta.dy / 2 + _bottomItemHeight <= 0.0) {
          // Refresh回弹完毕，恢复正常ListView的滑动状态
          _checkStateAndCallback(AnimationStates.RefreshBoxIdle, RefreshBoxDirectionStatus.IDLE);
          _bottomItemHeight = 0.0;
          widget.scrollPhysicsChanged(new RefreshAlwaysScrollPhysics());
        } else {
          if (_bottomItemHeight > 25.0 + _loadHeight) {
            if (_isPulling) {
              return;
            }
            _isPulling = true;
            // 如果是触发刷新则设置延时，等待列表高度渲染完成
            if (_isPushing) {
              new Future.delayed(const Duration(milliseconds: 200), () async {
                widget.scrollPhysicsChanged(new NeverScrollableScrollPhysics());
                _animationController.forward();
              });
            }else {
              widget.scrollPhysicsChanged(new NeverScrollableScrollPhysics());
              _animationController.forward();
            }
          } else if (_bottomItemHeight > 10.0 + _loadHeight) {
            _bottomItemHeight = -notification.dragDetails.delta.dy / 6 + _bottomItemHeight;
          } else if (_bottomItemHeight > _loadHeight) {
            _checkStateAndCallback(AnimationStates.DragAndRefreshEnabled, RefreshBoxDirectionStatus.PUSH);
            _bottomItemHeight = -notification.dragDetails.delta.dy / 4 + _bottomItemHeight;
          } else {
            _checkStateAndCallback(AnimationStates.DragAndRefreshNotEnabled, RefreshBoxDirectionStatus.PUSH);
            _bottomItemHeight = -notification.dragDetails.delta.dy / 2 + _bottomItemHeight;
          }
        }
      });
    }
  }

  void _checkStateAndCallback(AnimationStates currentState, RefreshBoxDirectionStatus refreshBoxDirectionStatus) {
    if (_animationStates != currentState) {
      // 下拉刷新回调
      if (refreshBoxDirectionStatus == RefreshBoxDirectionStatus.PULL) {
        // 释放刷新
        if (currentState == AnimationStates.DragAndRefreshEnabled) {
          this._refreshHeader.getKey().currentState.onRefreshReady();
        }
        // 刷新数据
        else if (currentState == AnimationStates.StartLoadData) {
          this._refreshHeader.getKey().currentState.onRefreshing();
        }
        // 刷新完成
        else if (currentState == AnimationStates.LoadDataEnd) {
          this._refreshHeader.getKey().currentState.onRefreshed();
        }
        // 刷新重置
        else if (currentState == AnimationStates.DragAndRefreshNotEnabled) {
          this._refreshHeader.getKey().currentState.onRefreshReset();
        }
      }
      // 上拉加载
      else if (refreshBoxDirectionStatus == RefreshBoxDirectionStatus.PUSH) {
        // 释放加载
        if (currentState == AnimationStates.DragAndRefreshEnabled) {
          this._refreshFooter.getKey().currentState.onLoadReady();
        }
        // 加载数据
        else if (currentState == AnimationStates.StartLoadData) {
          this._refreshFooter.getKey().currentState.onLoading();
          // 记录当前条数
          this._itemCount = widget.child.semanticChildCount;
        }
        // 加载完成
        else if (currentState == AnimationStates.LoadDataEnd) {
          _isPushing = false;
          // 判断是否加载出更多数据
          if (widget.child.semanticChildCount > this._itemCount) {
            this._refreshFooter.getKey().currentState.onLoaded();
          }else {
            this._refreshFooter.getKey().currentState.onNoMore();
          }
        }
        // 刷新重置
        else if (currentState == AnimationStates.DragAndRefreshNotEnabled) {
          this._refreshFooter.getKey().currentState.onLoadReset();
        }
      } else if (refreshBoxDirectionStatus == RefreshBoxDirectionStatus.IDLE) {
        // 重置
        if (currentState == AnimationStates.RefreshBoxIdle) {
          if (_lastStates == RefreshBoxDirectionStatus.PULL) {
            this._refreshHeader.getKey().currentState.onRefreshReset();
          } else if (_lastStates == RefreshBoxDirectionStatus.PUSH) {
            this._refreshFooter.getKey().currentState.onLoadReset();
          }
        }
      }
      _animationStates = currentState;
      _lastStates = refreshBoxDirectionStatus;
      if (widget.animationStateChangedCallback != null) {
        widget.animationStateChangedCallback(_animationStates, refreshBoxDirectionStatus);
      }
    }
  }
}

/// 切记 继承ScrollPhysics  必须重写applyTo，，在NeverScrollableScrollPhysics类里面复制就可以
/// 出现反向滑动时用此ScrollPhysics
class RefreshScrollPhysics extends ScrollPhysics {
  const RefreshScrollPhysics({ScrollPhysics parent}) : super(parent: parent);

  @override
  RefreshScrollPhysics applyTo(ScrollPhysics ancestor) {
    return new RefreshScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    return true;
  }

  //重写这个方法为了减缓ListView滑动速度
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (offset < 0.0) {
      return 0.00000000000001;
    }
    if (offset == 0.0) {
      return 0.0;
    }
    return offset / 2;
  }

  //此处返回null时为了取消惯性滑动
  @override
  Simulation createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    return null;
  }
}

/// 切记 继承ScrollPhysics  必须重写applyTo，，在NeverScrollableScrollPhysics类里面复制就可以
/// 此类用来控制IOS过度滑动出现弹簧效果
class RefreshAlwaysScrollPhysics extends AlwaysScrollableScrollPhysics {
  const RefreshAlwaysScrollPhysics({ScrollPhysics parent})
      : super(parent: parent);

  @override
  RefreshAlwaysScrollPhysics applyTo(ScrollPhysics ancestor) {
    return new RefreshAlwaysScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    return true;
  }

  /// 防止ios设备上出现弹簧效果
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    assert(() {
      if (value == position.pixels) {
        throw FlutterError(
            '$runtimeType.applyBoundaryConditions() was called redundantly.\n'
            'The proposed new position, $value, is exactly equal to the current position of the '
            'given ${position.runtimeType}, ${position.pixels}.\n'
            'The applyBoundaryConditions method should only be called when the value is '
            'going to actually change the pixels, otherwise it is redundant.\n'
            'The physics object in question was:\n'
            '  $this\n'
            'The position object in question was:\n'
            '  $position\n');
      }
      return true;
    }());
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) // underScroll
      return value - position.pixels;
    if (position.maxScrollExtent <= position.pixels &&
        position.pixels < value) // overScroll
      return value - position.pixels;
    if (value < position.minScrollExtent &&
        position.minScrollExtent < position.pixels) // hit top edge
      return value - position.minScrollExtent;
    if (position.pixels < position.maxScrollExtent &&
        position.maxScrollExtent < value) // hit bottom edge
      return value - position.maxScrollExtent;
    return 0.0;
  }

  /// 防止ios设备出现卡顿
  @override
  Simulation createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final Tolerance tolerance = this.tolerance;
    if (position.outOfRange) {
      double end;
      if (position.pixels > position.maxScrollExtent)
        end = position.maxScrollExtent;
      if (position.pixels < position.minScrollExtent)
        end = position.minScrollExtent;
      assert(end != null);
      return ScrollSpringSimulation(spring, position.pixels,
          position.maxScrollExtent, math.min(0.0, velocity),
          tolerance: tolerance);
    }
    if (velocity.abs() < tolerance.velocity) return null;
    if (velocity > 0.0 && position.pixels >= position.maxScrollExtent)
      return null;
    if (velocity < 0.0 && position.pixels <= position.minScrollExtent)
      return null;
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      tolerance: tolerance,
    );
  }
}
