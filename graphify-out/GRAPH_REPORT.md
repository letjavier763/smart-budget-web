# Graph Report - proyecto_app  (2026-05-23)

## Corpus Check
- 70 files · ~128,884 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 555 nodes · 938 edges · 43 communities (26 shown, 17 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 14 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]

## God Nodes (most connected - your core abstractions)
1. `payments_screen.dart` - 39 edges
2. `package:flutter/material.dart` - 32 edges
3. `../services/firestore_service.dart` - 30 edges
4. `package:firebase_auth/firebase_auth.dart` - 26 edges
5. `settings_screen.dart` - 22 edges
6. `package:cloud_firestore/cloud_firestore.dart` - 19 edges
7. `../main.dart` - 18 edges
8. `activity_screen.dart` - 16 edges
9. `dart:convert` - 15 edges
10. `build` - 14 edges

## Surprising Connections (you probably didn't know these)
- `Pubspec Manifest` --conceptually_related_to--> `SmartBudget Brand`  [INFERRED]
  pubspec.yaml → diseños.html
- `../main.dart` --defines--> `main()`  [EXTRACTED]
  lib/home/settings_screen.dart → linux/runner/main.cc
- `Launcher Icon (HDPI)` --conceptually_related_to--> `iOS App Store Icon`  [INFERRED]
  android/app/src/main/res/mipmap-hdpi/ic_launcher.png → ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png
- `main()` --calls--> `my_application_new()`  [INFERRED]
  linux/runner/main.cc → linux/runner/my_application.cc
- `Analysis Options` --references--> `Flutter Lints Package`  [EXTRACTED]
  analysis_options.yaml → pubspec.yaml

## Communities (43 total, 17 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.06
Nodes (50): AlertDialog, build, Card, Center, CheckboxListTile, Column, Container, dispose (+42 more)

### Community 1 - "Community 1"
Cohesion: 0.05
Nodes (45): auth_service.dart, AuthService, Exception, build, dispose, ForgotPasswordScreen, _ForgotPasswordScreenState, Scaffold (+37 more)

### Community 2 - "Community 2"
Cohesion: 0.07
Nodes (41): activity_screen.dart, _ActivityItem, ActivityScreen, _ActivityScreenState, build, Center, Column, _emptyState (+33 more)

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (43): AlertDialog, Align, _BalanceCard, BoxDecoration, build, _categoryIcon, Center, Column (+35 more)

### Community 4 - "Community 4"
Cohesion: 0.07
Nodes (41): DefaultFirebaseOptions, UnsupportedError, Text, AlertDialog, build, changeLanguage, Divider, initState (+33 more)

### Community 5 - "Community 5"
Cohesion: 0.05
Nodes (41): AdminDashboardScreen, _AdminDashboardScreenState, build, _buildAnalyticsTab, _buildBarChart, _buildChartCard, _buildGroupsTab, _buildLegendItem (+33 more)

### Community 6 - "Community 6"
Cohesion: 0.08
Nodes (31): AlertDialog, _areFriendListsEqual, build, Card, Center, Column, Container, dispose (+23 more)

### Community 7 - "Community 7"
Cohesion: 0.09
Nodes (32): build, _buildHistoryTab, _buildRequestsTab, Card, _categoryIcon, Center, Column, Container (+24 more)

### Community 8 - "Community 8"
Cohesion: 0.06
Nodes (29): AdminDashboardScreen, Badge, build, _buildNavItem, FriendsScreen, GestureDetector, GroupsScreen, Icon (+21 more)

### Community 9 - "Community 9"
Cohesion: 0.12
Nodes (19): RegisterPlugins(), FlutterWindow(), OnCreate(), Create(), Destroy(), EnableFullDpiSupportIfAvailable(), GetClientArea(), GetThisFromHandle() (+11 more)

### Community 10 - "Community 10"
Cohesion: 0.11
Nodes (17): Analysis Options, Cloud Firestore, Design System & Login UI, Firebase Auth, Firebase Core, RegisterGeneratedPlugins(), Flutter Launcher Icons, Flutter Lints Package (+9 more)

### Community 11 - "Community 11"
Cohesion: 0.1
Nodes (20): ../auth/auth_service.dart, build, _buildProfileListTile, Card, initState, ProfileScreen, _ProfileScreenState, Scaffold (+12 more)

### Community 12 - "Community 12"
Cohesion: 0.15
Nodes (14): main, fl_register_plugins(), package:flutter_test/flutter_test.dart, package:proyecto_app/main.dart, main(), first_frame_cb(), my_application_activate(), my_application_class_init() (+6 more)

### Community 13 - "Community 13"
Cohesion: 0.39
Nodes (3): FlutterAppDelegate, FlutterImplicitEngineDelegate, AppDelegate

### Community 14 - "Community 14"
Cohesion: 0.25
Nodes (7): build, Color, Container, getBrandBgColor, GroupAvatar, GroupBrandStyle, _normalizeString

### Community 15 - "Community 15"
Cohesion: 0.29
Nodes (7): GRAPH_REPORT.md, graphify agent, graphify explain, graphify query, graphify update, skill tool, wiki/index.md

### Community 16 - "Community 16"
Cohesion: 0.47
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

## Knowledge Gaps
- **272 isolated node(s):** `MainActivity`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `DefaultFirebaseOptions`, `UnsupportedError`, `main` (+267 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `Community 1` to `Community 0`, `Community 2`, `Community 3`, `Community 4`, `Community 5`, `Community 6`, `Community 7`, `Community 8`, `Community 11`, `Community 12`, `Community 14`?**
  _High betweenness centrality (0.242) - this node is a cross-community bridge._
- **Why does `main()` connect `Community 12` to `Community 4`?**
  _High betweenness centrality (0.187) - this node is a cross-community bridge._
- **Why does `../main.dart` connect `Community 4` to `Community 1`, `Community 2`, `Community 12`?**
  _High betweenness centrality (0.159) - this node is a cross-community bridge._
- **What connects `MainActivity`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `DefaultFirebaseOptions` to the rest of the system?**
  _272 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._