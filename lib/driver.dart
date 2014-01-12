// Copyright (c) 2014, Google Inc. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// Author: Paul Brauner (polux@google.com)

library driver;

import 'package:meta_dart/interpreter.dart';
import 'package:meta_dart/parser.dart';
import 'package:meta_dart/pretty.dart';

class ParseError {
  final int row;
  final int column;
  final String message;
  ParseError(this.row, this.column, this.message);
}

class ExecutionResult {
  final ParseError parseError;
  final String output;

  ExecutionResult.fromParseError(this.parseError) : output = null;
  ExecutionResult.fromOutput(this.output) : parseError = null;

  match({parseError(ParseError parseError), someOutput(String output)}) {
    return (this.parseError != null)
        ? parseError(this.parseError)
        : someOutput(this.output);
  }
}

final _parser = new SDartParsers().start;

ExecutionResult execute(String program) {
  try {
    final parseResult = _parser.run(program);
    if (parseResult.isSuccess) {
      final buffer = new StringBuffer();
      logExpression(expression) {
        buffer.writeln("▶ ${pretty(expression)}");
      }
      logError(exception) {
        buffer.writeln("▷ ${exception}");
      }
      eval(new SDartParsers().start.parse(program), logExpression, logError);
      return new ExecutionResult.fromOutput(buffer.toString());
    } else {
      final pos = parseResult.expectations.position;
      return new ExecutionResult.fromParseError(
          new ParseError(pos.line - 1,
                         pos.character,
                         parseResult.errorMessage));
    }
  } catch (e) {
    return new ExecutionResult.fromOutput(e.toString());
  }
}