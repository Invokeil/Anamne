import 'package:sembast_web/sembast_web.dart';

Future<Database> openAnamneDatabase() =>
    databaseFactoryWeb.openDatabase('anamne');
