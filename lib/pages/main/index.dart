import 'package:flutter/material.dart';
import 'package:qingyun_todo/constants/main.dart';
import 'package:qingyun_todo/pages/period/index.dart';
import 'package:qingyun_todo/pages/schedule/index.dart';
import 'package:qingyun_todo/pages/statistics/index.dart';
import 'package:qingyun_todo/pages/todo/index.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // 各个页面视图
  List<Widget> getChildrenList() {
    return [
      const TodoView(),
      const PeriodView(),
      const ScheduleView(),
      const StatisticsView(),
    ];
  }

  // 导航栏下标位置
  int _currentIndex = 0;

  // 导航栏列表数据
  final List<Map<String, String>> tabList = MainContants.bottomTabList;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Color.fromARGB(255, 235, 235, 235),
      body: IndexedStack(index: _currentIndex, children: getChildrenList()),
      bottomNavigationBar: _getBottomNavTabWidget(),
      // 👇 新增浮动按钮，根据当前索引控制显示
      floatingActionButton:
          _currentIndex ==
              0 // 假设 TodoView 的索引是 0
          ? FloatingActionButton(
              shape: CircleBorder(),
              onPressed: () {
                // 触发 TodoView 的添加逻辑（后面说明如何通信）
                _handleAddTodo();
              },
              backgroundColor: Colors.deepPurpleAccent,
              child: const Icon(Icons.add),
            )
          : null, // 其他页面不显示
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // 处理添加待办事件
  void _handleAddTodo() {
    // 方式1：通过 GlobalKey 获取 TodoView 状态并调用方法（不推荐）
    // 方式2：使用状态管理（推荐），下面会展示如何用 ValueNotifier 实现
  }

  // 底部导航栏
  Widget _getBottomNavTabWidget() {
    return Container(
      // 外边距 & 导航栏底部阴影
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRRect(
        // 圆角
        borderRadius: BorderRadius.circular(50),
        child: BottomNavigationBar(
          showSelectedLabels: false,
          selectedLabelStyle: TextStyle(
            fontSize: 12,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
          showUnselectedLabels: false,
          useLegacyColorScheme: false,
          items: getTabBarWidget(),
          currentIndex: _currentIndex,
          elevation: 0,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
        ),
      ),
    );
  }

  // 底部导航栏元素
  List<BottomNavigationBarItem> getTabBarWidget() {
    return List.generate(tabList.length, (index) {
      return BottomNavigationBarItem(
        icon: Image.asset(tabList[index]['icon']!, width: 33, height: 33),
        activeIcon: Image.asset(
          tabList[index]['active_icon']!,
          width: 33,
          height: 33,
        ),
        label: tabList[index]['name']!,
      );
    });
  }
}
