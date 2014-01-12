// Copyright (c) 2013, Google Inc. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// Author: Paul Brauner (polux@google.com)

import 'package:adts/build.dart';
import 'package:adts/configuration.dart';

const CONFIG = const Configuration(
    finalFields: true,
    isGetters: false,
    asGetters: false,
    copyMethod: false,
    equality: false,
    toStringMethod: true,
    visitor: false,
    matchMethod: true,
    toJson: false,
    fromJson: false);

main(arguments) {
  build(arguments, CONFIG);
}
