import 'package:flutter/material.dart';
import 'package:qingyun_todo/contants/main.dart';
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
    return [const TodoView(), const PeriodView(), const StatisticsView(), const ScheduleView()];
  }

  // 导航栏下标位置
  int _currentIndex = 0;

  // 导航栏列表数据
  final List<Map<String, String>> tabList = MainContants.bottomTabList;

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

  // 底部导航栏
  Widget _getBottomNavTabWidget() {
    return Container(
      // 外边距 & 导航栏底部阴影
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 159, 88, 88).withOpacity(0.6),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: getChildrenList()),
      bottomNavigationBar: _getBottomNavTabWidget(),
    );
  }
}
