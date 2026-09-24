# 青云待办 (QingYun Todo) - 项目汇总文档

## 📋 项目概述

**项目名称**: qingyun_todo  
**项目描述**: 一款基于 Flutter 开发的跨平台待办事项管理应用  
**当前版本**: 1.0.0+1  
**开发语言**: Dart (SDK ^3.11.1)  
**框架**: Flutter  

---

## 🎯 核心功能模块

### 1. 待办管理 (Todo)
- ✅ 任务创建、编辑、删除
- ✅ 任务完成状态切换
- ✅ 优先级分类（高/中/低/无）
- ✅ 截止日期提醒
- ✅ 子任务进度追踪
- ✅ 逾期任务标识
- ✅ 今日进度统计

### 2. 周期任务 (Period)
- 🔄 自定义周期间隔设置
- 🔄 周期任务自动生成
- 🔄 周期完成计数统计
- ⏳ *功能开发中*

### 3. 日程管理 (Schedule)
- 📅 日程视图展示
- 📅 时间线规划
- ⏳ *功能开发中*

### 4. 数据统计 (Statistics)
- 📊 任务完成率分析
- 📊 周期任务统计
- 📊 趋势图表展示
- ⏳ *功能开发中*

---

## 🏗️ 项目架构

### 目录结构
```
lib/
├── main.dart                 # 应用入口
├── api/                      # API 接口层（待实现）
├── assets/                   # 静态资源
├── components/               # 通用组件
│   └── todo_tag.dart         # 标签组件
├── constants/                # 常量定义
│   └── routes.dart           # 路由常量
├── models/                   # 数据模型
│   └── todo.dart             # 待办数据模型
├── pages/                    # 页面视图
│   ├── main/                 # 主页面（底部导航）
│   ├── todo/                 # 待办页面
│   │   ├── index.dart
│   │   └── widgets/
│   │       ├── todo_card.dart
│   │       ├── today_progress.dart
│   │       └── section_header.dart
│   ├── period/               # 周期页面
│   ├── schedule/             # 日程页面
│   └── statistics/           # 统计页面
├── routes/                   # 路由配置
│   └── index.dart
├── stores/                   # 状态管理（待实现）
├── utils/                    # 工具类（待实现）
└── viewmodels/               # 视图模型（待实现）
```

### 技术栈
- **UI 框架**: Flutter + Cupertino (iOS 风格)
- **网络请求**: Dio ^5.10.0
- **状态管理**: 待集成
- **本地存储**: 待集成
- **路由管理**: Navigator 命名路由

---

## 🗄️ 数据库设计

### 表1: `periodic_configs` (周期配置表)
| 字段名 | 类型 | 说明 |
|--------|------|------|
| id | INTEGER PK | 主键自增 |
| name | TEXT NOT NULL | 周期名称 |
| start_date | TEXT NOT NULL | 起始日期 (YYYY-MM-DD) |
| interval_days | INTEGER | 周期间隔天数 |
| completed_count | INTEGER | 已完成计数 |
| remark | TEXT | 备注 |
| created_at | TEXT | 创建时间 |
| updated_at | TEXT | 更新时间 |

### 表2: `tasks` (待办任务表)
| 字段名 | 类型 | 说明 |
|--------|------|------|
| id | INTEGER PK | 主键自增 |
| title | TEXT NOT NULL | 任务标题 |
| remark | TEXT | 备注 |
| remind_date | TEXT NOT NULL | 提醒日期 |
| remind_time | TEXT | 提醒时间 (HH:mm) |
| priority_color | TEXT | 优先级颜色 |
| is_completed | INTEGER | 完成状态 (0/1) |
| periodic_id | INTEGER FK | 关联周期ID |
| source_type | TEXT | 类型 (REGULAR/PERIODIC) |
| created_at | TEXT | 创建时间 |
| updated_at | TEXT | 更新时间 |

---

## 🎨 UI/UX 设计亮点

### 设计风格
- **iOS 原生风格**: 采用 Cupertino 组件库
- **毛玻璃效果**: 底部导航栏 BackdropFilter 模糊
- **胶囊式设计**: 圆角按钮、卡片、导航栏
- **动态配色**: 优先级颜色标识系统

### 交互特性
- ✅ 流畅的动画过渡 (AnimatedContainer, AnimatedSwitcher)
- ✅ 手势反馈 (GestureDetector + InkWell)
- ✅ 弹性滚动 (BouncingScrollPhysics)
- ✅ 大标题导航栏 (CupertinoSliverNavigationBar)

### 颜色系统
```dart
// 主色调
Primary Blue:    #007AFF  // iOS 系统蓝
Success Green:   #34C759  // 完成状态
Warning Orange:  #FF9500  // 中等优先级
Danger Red:      #FF3B30  // 高优先级/逾期
Neutral Gray:    #8E8E93  // 次要文本
Background:      #F2F2F7  // 页面背景
```

---

## 📦 依赖清单

### 生产依赖
- `flutter`: SDK
- `cupertino_icons`: ^1.0.8 (iOS 图标)
- `dio`: ^5.10.0 (HTTP 客户端)

### 开发依赖
- `flutter_test`: SDK
- `flutter_lints`: ^6.0.0 (代码规范)

---

## 🚀 当前进度

### 已完成 ✅
- [x] 项目基础架构搭建
- [x] 底部导航栏 (4个Tab)
- [x] 待办列表页面完整实现
- [x] 待办卡片组件 (色带+勾选+标签)
- [x] 今日进度条组件
- [x] 分组标题组件 (可折叠)
- [x] 数据模型定义 (Todo, TodoPriority)
- [x] 数据库表结构设计
- [x] Mock 数据演示

### 进行中 🚧
- [ ] 周期任务页面
- [ ] 日程管理页面
- [ ] 数据统计页面

### 待实现 ⏳
- [ ] 状态管理集成 (Provider/Riverpod/Bloc)
- [ ] 本地数据库集成 (SQLite/Hive)
- [ ] API 接口对接
- [ ] 任务 CRUD 操作
- [ ] 周期任务自动生成逻辑
- [ ] 提醒通知功能
- [ ] 数据持久化
- [ ] 单元测试 & Widget 测试

---

## 🔧 待优化项

1. **状态管理**: 当前使用 setState，需引入专业状态管理方案
2. **数据层**: api/stores/utils/viewmodels 目录为空，需补充实现
3. **路由系统**: 仅配置主页路由，需扩展子页面路由
4. **错误处理**: 缺少统一的异常处理机制
5. **国际化**: 硬编码中文字符串，需提取为多语言资源
6. **主题适配**: 仅支持浅色模式，需增加深色模式
7. **性能优化**: 长列表需考虑虚拟化渲染

---

## 📝 开发规范

### 代码风格
- 遵循 `flutter_lints` 规范
- 使用 `analysis_options.yaml` 配置
- 私有成员以 `_` 前缀命名
- Widget 类使用 PascalCase
- 文件名使用 snake_case

### 注释规范
- 类和公共方法使用 `///` 文档注释
- 关键逻辑添加行内注释
- TODO 标记待办事项

---

## 🎯 下一步计划

### Phase 1: 核心功能完善
1. 集成状态管理框架
2. 实现本地数据库存储
3. 完成任务 CRUD 功能
4. 实现周期任务生成逻辑

### Phase 2: 页面补全
1. 周期配置管理页面
2. 日程日历视图
3. 统计图表展示

### Phase 3: 体验优化
1. 添加任务详情编辑页
2. 实现提醒通知
3. 支持拖拽排序
4. 数据导入导出

### Phase 4: 发布准备
1. 完善单元测试
2. 性能测试与优化
3. 应用图标与启动图
4. 打包发布流程

---

## 📞 联系信息

- **项目仓库**: 本地 Git 仓库
- **最后更新**: 2026年8月21日
- **开发者**: QingYun Team

---

*本文档由 AI 自动生成，基于项目源码分析。如有变更请及时更新。*
