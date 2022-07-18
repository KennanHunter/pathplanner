import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pathplanner/pages/welcome_page.dart';
import 'package:pathplanner/robot_path/robot_path.dart';
import 'package:pathplanner/services/undo_redo.dart';
import 'package:pathplanner/widgets/custom_appbar.dart';
import 'package:pathplanner/widgets/deploy_fab.dart';
import 'package:pathplanner/widgets/path_tile.dart';
import 'package:pathplanner/widgets/field_image.dart';
import 'package:pathplanner/widgets/keyboard_shortcuts.dart';
import 'package:pathplanner/widgets/path_editor/path_editor.dart';
import 'package:pathplanner/widgets/dialogs/settings_dialog.dart';
import 'package:pathplanner/widgets/pplib_update_card.dart';
import 'package:pathplanner/widgets/update_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  final FieldImage defaultFieldImage;
  final String appVersion;
  final bool appStoreBuild;
  final SharedPreferences prefs;
  final ValueChanged<Color> onTeamColorChanged;

  HomePage({
    required this.defaultFieldImage,
    required this.appVersion,
    required this.appStoreBuild,
    required this.prefs,
    required this.onTeamColorChanged,
    super.key,
  });

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  Directory? _projectDir;
  List<RobotPath> _paths = [];
  RobotPath? _currentPath;
  Size _robotSize = Size(0.75, 1.0);
  bool _holonomicMode = false;
  bool _generateJSON = false;
  bool _generateCSV = false;
  bool _isWpiLib = false;
  SecureBookmarks? _bookmarks = Platform.isMacOS ? SecureBookmarks() : null;
  List<FieldImage> _fieldImages = FieldImage.offialFields();
  FieldImage? _fieldImage;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();

    _animController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 250));
    _scaleAnimation =
        CurvedAnimation(parent: _animController, curve: Curves.ease);

    _loadFieldImages().then((_) async {
      String? projectDir = widget.prefs.getString('currentProjectDir');
      if (projectDir != null && Platform.isMacOS) {
        if (widget.prefs.getString('macOSBookmark') != null) {
          await _bookmarks!
              .resolveBookmark(widget.prefs.getString('macOSBookmark')!);

          await _bookmarks!
              .startAccessingSecurityScopedResource(File(projectDir));
        } else {
          projectDir = null;
        }
      }

      if (projectDir == null) {
        projectDir = await Navigator.push(
          _key.currentContext!,
          PageRouteBuilder(
            pageBuilder: (context, anim1, anim2) => WelcomePage(
              backgroundImage: widget.defaultFieldImage,
              appVersion: widget.appVersion,
            ),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );

        widget.prefs.setString('currentProjectDir', projectDir!);

        if (Platform.isMacOS) {
          // Bookmark project on macos so it can be accessed again later
          String bookmark = await _bookmarks!.bookmark(File(projectDir));
          widget.prefs.setString('macOSBookmark', bookmark);
        }
      }

      setState(() {
        _projectDir = Directory(projectDir!);

        _paths = _loadPaths(_projectDir!);
        _isWpiLib = _isWpiLibProject(_projectDir!);
        _currentPath = _paths[0];
        _robotSize = Size(widget.prefs.getDouble('robotWidth') ?? 0.75,
            widget.prefs.getDouble('robotLength') ?? 1.0);
        _holonomicMode = widget.prefs.getBool('holonomicMode') ?? false;
        _generateJSON = widget.prefs.getBool('generateJSON') ?? false;
        _generateCSV = widget.prefs.getBool('generateCSV') ?? false;

        String? selectedFieldName = widget.prefs.getString('fieldImage');
        if (selectedFieldName != null) {
          for (FieldImage image in _fieldImages) {
            if (image.name == selectedFieldName) {
              _fieldImage = image;
              break;
            }
          }
        }

        _animController.forward();
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    if (Platform.isMacOS && _projectDir != null) {
      _bookmarks!.stopAccessingSecurityScopedResource(File(_projectDir!.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _key,
      appBar: CustomAppBar(
        titleText: _currentPath == null ? 'PathPlanner' : _currentPath!.name,
      ),
      drawer: _projectDir == null ? null : _buildDrawer(context),
      body: ScaleTransition(
        scale: _scaleAnimation,
        child: _buildBody(),
      ),
      floatingActionButton: Visibility(
        visible: _isWpiLib &&
            _projectDir != null &&
            !(widget.appStoreBuild && Platform.isMacOS),
        child: DeployFAB(projectDir: _projectDir),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topRight: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
      child: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              child: Stack(
                children: [
                  Container(
                    child: Align(
                        alignment: FractionalOffset.bottomRight,
                        child: Text(
                          'v' + widget.appVersion,
                          style: TextStyle(color: colorScheme.onSurface),
                        )),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Container(),
                          flex: 2,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            basename(_projectDir!.path),
                            style: TextStyle(
                              fontSize: 20,
                            ),
                          ),
                        ),
                        ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              onPrimary: colorScheme.onPrimaryContainer,
                              primary: colorScheme.primaryContainer,
                            ),
                            onPressed: () {
                              _openProjectDialog(context);
                            },
                            child: Text('Switch Project')),
                        Expanded(
                          child: Container(),
                          flex: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (int i = 0; i < _paths.length; i++)
                    PathTile(
                      path: _paths[i],
                      key: Key('$i'),
                      isSelected: _paths[i] == _currentPath,
                      onRename: (name) {
                        Directory pathsDir = _getPathsDir(_projectDir!);

                        File pathFile =
                            File(join(pathsDir.path, _paths[i].name + '.path'));
                        File newPathFile =
                            File(join(pathsDir.path, name + '.path'));
                        if (newPathFile.existsSync() &&
                            newPathFile.path != pathFile.path) {
                          Navigator.of(context).pop();
                          showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return KeyBoardShortcuts(
                                  keysToPress: {LogicalKeyboardKey.enter},
                                  onKeysPressed: Navigator.of(context).pop,
                                  child: AlertDialog(
                                    title: Text('Unable to Rename'),
                                    content: Text(
                                        'The file "${basename(newPathFile.path)}" already exists'),
                                    actions: [
                                      TextButton(
                                        onPressed: Navigator.of(context).pop,
                                        child: Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                              });
                          return false;
                        } else {
                          pathFile.rename(join(pathsDir.path, name + '.path'));
                          setState(() {
                            //flutter weird
                            _currentPath!.name = _currentPath!.name;
                          });
                          return true;
                        }
                      },
                      onTap: () {
                        setState(() {
                          _currentPath = _paths[i];
                          UndoRedo.clearHistory();
                        });
                      },
                      onDelete: () {
                        UndoRedo.clearHistory();

                        Directory pathsDir = _getPathsDir(_projectDir!);

                        File pathFile =
                            File(join(pathsDir.path, _paths[i].name + '.path'));

                        if (pathFile.existsSync()) {
                          // The fitted text field container does not rebuild
                          // itself correctly so this is a way to hide it and
                          // avoid confusion. (Hides drawer)
                          Navigator.of(context).pop();

                          showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                void confirm() {
                                  Navigator.of(context).pop();
                                  pathFile.delete();
                                  setState(() {
                                    if (_currentPath == _paths.removeAt(i)) {
                                      _currentPath = _paths.first;
                                    }
                                  });
                                }

                                return KeyBoardShortcuts(
                                  keysToPress: {LogicalKeyboardKey.enter},
                                  onKeysPressed: confirm,
                                  child: AlertDialog(
                                    title: Text('Delete Path'),
                                    content: Text(
                                        'Are you sure you want to delete "${_paths[i].name}"? This cannot be undone.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                        child: Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: confirm,
                                        child: Text('Confirm'),
                                      ),
                                    ],
                                  ),
                                );
                              });
                        } else {
                          setState(() {
                            if (_currentPath == _paths.removeAt(i)) {
                              _currentPath = _paths.first;
                            }
                          });
                        }
                      },
                      onDuplicate: () {
                        UndoRedo.clearHistory();

                        setState(() {
                          List<String> pathNames = [];
                          for (RobotPath path in _paths) {
                            pathNames.add(path.name);
                          }
                          String pathName = _paths[i].name + ' Copy';
                          while (pathNames.contains(pathName)) {
                            pathName = pathName + ' Copy';
                          }
                          _paths.add(RobotPath(
                            waypoints: RobotPath.cloneWaypointList(
                                _paths[i].waypoints),
                            name: pathName,
                          ));
                          _currentPath = _paths.last;
                          _savePath(_currentPath!);
                        });
                      },
                    ),
                ],
              ),
            ),
            Container(
              child: Align(
                alignment: FractionalOffset.bottomCenter,
                child: Container(
                  child: Column(
                    children: [
                      Divider(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0, top: 4.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                List<String> pathNames = [];
                                for (RobotPath path in _paths) {
                                  pathNames.add(path.name);
                                }
                                String pathName = 'New Path';
                                while (pathNames.contains(pathName)) {
                                  pathName = 'New ' + pathName;
                                }
                                setState(() {
                                  _paths.add(
                                      RobotPath.defaultPath(name: pathName));
                                  _currentPath = _paths.last;
                                  _savePath(_currentPath!);
                                  UndoRedo.clearHistory();
                                });
                              },
                              icon: Icon(Icons.add),
                              label: Text('Add Path'),
                              style: ElevatedButton.styleFrom(
                                primary: colorScheme.primaryContainer,
                                onPrimary: colorScheme.onPrimaryContainer,
                                fixedSize: Size(135, 56),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return SettingsDialog(
                                      prefs: widget.prefs,
                                      onTeamColorChanged:
                                          widget.onTeamColorChanged,
                                      fieldImages: _fieldImages,
                                      selectedField: _fieldImage ??
                                          widget.defaultFieldImage,
                                      onFieldSelected: (FieldImage image) {
                                        setState(() {
                                          _fieldImage = image;
                                          if (!_fieldImages.contains(image)) {
                                            _fieldImages.add(image);
                                          }
                                          widget.prefs.setString(
                                              'fieldImage', image.name);
                                        });
                                      },
                                      onSettingsChanged: () {
                                        setState(() {
                                          _robotSize = Size(
                                              widget.prefs.getDouble(
                                                      'robotWidth') ??
                                                  0.75,
                                              widget.prefs.getDouble(
                                                      'robotLength') ??
                                                  1.0);
                                          _holonomicMode = widget.prefs
                                                  .getBool('holonomicMode') ??
                                              false;
                                          _generateJSON = widget.prefs
                                                  .getBool('generateJSON') ??
                                              false;
                                          _generateCSV = widget.prefs
                                                  .getBool('generateCSV') ??
                                              false;
                                        });
                                      },
                                      onGenerationEnabled: () {
                                        for (RobotPath path in _paths) {
                                          _savePath(path);
                                        }
                                      },
                                    );
                                  },
                                );
                              },
                              icon: Icon(Icons.settings),
                              label: Text('Settings'),
                              style: ElevatedButton.styleFrom(
                                primary: colorScheme.surface,
                                onPrimary: colorScheme.onSurface,
                                fixedSize: Size(135, 56),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_projectDir != null) {
      return Stack(
        children: [
          Center(
            child: Container(
              child: PathEditor(
                fieldImage: _fieldImage ?? widget.defaultFieldImage,
                path: _currentPath!,
                robotSize: _robotSize,
                holonomicMode: _holonomicMode,
                showGeneratorSettings: _generateJSON || _generateCSV,
                savePath: (path) => _savePath(path),
                prefs: widget.prefs,
              ),
            ),
          ),
          Align(
            alignment: FractionalOffset.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.appStoreBuild)
                  UpdateCard(currentVersion: widget.appVersion),
                if (_isWpiLib && !(widget.appStoreBuild && Platform.isMacOS))
                  PPLibUpdateCard(projectDir: _projectDir!),
              ],
            ),
          ),
        ],
      );
    } else {
      return Container();
    }
  }

  List<RobotPath> _loadPaths(Directory projectDir) {
    List<RobotPath> paths = [];

    Directory pathsDir = _getPathsDir(projectDir);
    if (!pathsDir.existsSync()) {
      pathsDir.createSync(recursive: true);
    }

    List<FileSystemEntity> pathFiles = pathsDir.listSync();
    for (FileSystemEntity e in pathFiles) {
      if (e.path.endsWith('.path')) {
        String json = File(e.path).readAsStringSync();
        try {
          RobotPath p = RobotPath.fromJson(jsonDecode(json));
          p.name = basenameWithoutExtension(e.path);
          paths.add(p);
        } catch (e) {
          // Path is not in correct format. Don't add it
        }
      }
    }

    if (paths.isEmpty) {
      paths.add(RobotPath.defaultPath());
    }

    return paths;
  }

  Directory _getPathsDir(Directory projectDir) {
    if (_isWpiLibProject(projectDir)) {
      // Java or C++ project
      return Directory(
          join(projectDir.path, 'src', 'main', 'deploy', 'pathplanner'));
    } else {
      // Other language
      return Directory(join(projectDir.path, 'deploy', 'pathplanner'));
    }
  }

  bool _isWpiLibProject(Directory projectDir) {
    File buildFile = File(join(projectDir.path, 'build.gradle'));

    return buildFile.existsSync();
  }

  void _savePath(RobotPath path) {
    if (_projectDir != null) {
      path.savePath(_getPathsDir(_projectDir!), _generateJSON, _generateCSV);
    }
  }

  void _openProjectDialog(BuildContext context) async {
    String? projectFolder = await getDirectoryPath(
        confirmButtonText: 'Open Project',
        initialDirectory: Directory.current.path);
    if (projectFolder != null) {
      Directory pathsDir = _getPathsDir(Directory(projectFolder));

      pathsDir.createSync(recursive: true);
      widget.prefs.setString('currentProjectDir', projectFolder);
      widget.prefs.remove('pathOrder');

      if (Platform.isMacOS) {
        // Bookmark project on macos so it can be accessed again later
        String bookmark = await _bookmarks!.bookmark(File(projectFolder));
        widget.prefs.setString('macOSBookmark', bookmark);
      }

      setState(() {
        _projectDir = Directory(projectFolder);
        _paths = _loadPaths(_projectDir!);
        _isWpiLib = _isWpiLibProject(_projectDir!);
        _currentPath = _paths[0];
      });
    }
  }

  Future<void> _loadFieldImages() async {
    Directory appDir = await getApplicationSupportDirectory();
    Directory imagesDir = Directory(join(appDir.path, 'custom_fields'));

    imagesDir.createSync(recursive: true);

    List<FileSystemEntity> fileEntities = imagesDir.listSync();
    for (FileSystemEntity e in fileEntities) {
      _fieldImages.add(FieldImage.custom(File(e.path)));
    }
  }
}
