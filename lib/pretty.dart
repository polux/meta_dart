// Copyright (c) 2014, Google Inc. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// Author: Paul Brauner (polux@google.com)

library pretty;

import 'package:meta_dart/datatypes.dart';

// (?:) is 3
// unary ! and ~ are 14
// . and () are 15
final _BINOP_PRECEDENCES = {
  "||": 4,
  "&&": 5,
  "==": 6, "!=": 6,
  "<": 7, "<=": 7, ">": 7, ">=": 7,
  "|": 8,
  "&": 9,
  "^": 10,
  "<<": 11, ">>": 11,
  "+":12, "-": 12,
  "*":13, "/": 13, "%": 13, "~/": 13,
};

String _pretty(Expression expr, int precedence) {

  String parens(int maxPre, String str) {
    return (precedence > maxPre) ? "($str)" : str;
  }

  return expr.match(
    self: () => "this",
    constructorcall: (clazzName, args) {
      if (clazzName == "num" || clazzName == "bool") {
        return args[0].value.toString();
      } else {
        final prettyArgs = args.map((a) => _pretty(a, 0));
        return "new ${clazzName}(${prettyArgs.join(", ")})";
      }
    },
    variable: (x) => x,
    lambda: (params, body) => "(${params.join(", ")}) => ${_pretty(body, 0)}",
    functioncall: (fun, args) {
      final prettyArgs = args.map((a) => _pretty(a, 0));
      return "${_pretty(fun, 15)}(${prettyArgs.join(", ")})";
    },
    getsend: (receiver, name) => "${_pretty(receiver, 15)}.$name",
    send: (receiver, name, args) {
      final operatorPre = _BINOP_PRECEDENCES[name];
      if (operatorPre != null && args.length == 1) {
        final left = _pretty(receiver, operatorPre);
        final right = _pretty(args[0], operatorPre + 1);
        return parens(operatorPre, "$left $name $right");
      } else {
        final prettyArgs = args.map((a) => _pretty(a, 0));
        return "${_pretty(receiver, 15)}.$name(${prettyArgs.join(", ")})";
      }
    },
    ifthenelse: (cond, thenE, elseE) {
      return parens(3,
          "${_pretty(cond, 4)} ? ${_pretty(thenE, 3)} : ${_pretty(elseE, 3)}");
    },
    numlit: (n) => n.toString(),
    boollit: (b) => b.toString(),
    stringlit: (s) => '"$s"',
    brackets: (e) => "<${_pretty(e, 0)}>",
    escape: (e) => "~${_pretty(e, 14)}",
    run: (e) => "run(${_pretty(e, 0)})",
    lift: (e) => "lift(${_pretty(e, 0)})");
}

String pretty(Expression expr) => _pretty(expr, 0);