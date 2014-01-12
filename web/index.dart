// Copyright (c) 2014, Google Inc. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// Author: Paul Brauner (polux@google.com)

library index;

import 'package:meta_dart/driver.dart';
import 'package:ace/ace.dart' as ace;
import 'dart:html';

final EXAMPLE = """
class Arith {
  Arith();

  // the power function
  pow(x, e) => e == 0 ? 1 : x * this.pow(x, e-1);

  // partial application of pow to e = 3
  cube() => (x) => this.pow(x, 3);

  // the same function, annotated for multi-stage execution
  spow(x, e) => e == 0 ? <1> : <~x * ~this.spow(x, e - 1)>;

  // specialization of spow for e = 3
  scube() => run(<(x) => ~this.spow(<x>, 3)>);
}

main() {
  final arith = new Arith();
  final cube = arith.cube();
  final scube = arith.scube();

  print(cube);
  print(cube(5));
  print(scube);
  print(scube(5));
}""";

main() {
  final editor =
      ace.edit(querySelector('#buffer'))
          ..session.mode = new ace.Mode('ace/mode/dart')
          ..session.tabSize = 2
          ..fontSize = 16;
  final TextAreaElement output = querySelector('#result');

  editor.onChange.listen((_) {
    ExecutionResult result = execute(editor.value);
    result.match(
        parseError: (error) {
          output.value = '';
          final annotation = new ace.Annotation(
              row: error.row, text: error.message, type: "error");
          editor.session.annotations = [annotation];
        },
        someOutput: (str) {
          editor.session.annotations = [];
          output.value = str;
        });
  });
  editor.setValue(EXAMPLE, -1);
  editor.focus();
}