// Copyright (c) 2014, Google Inc. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// Author: Paul Brauner (polux@google.com)

library interpreter;

import 'package:meta_dart/datatypes.dart';
import 'package:meta_dart/pretty.dart';
import 'package:persistent/persistent.dart';

PersistentMap<String, Value> EMPTY_ENV = new PersistentMap<String, Value>();

Value _symbolValue(String x) => new SymbolValue(x);
Value _realValue(Expression e) => new RealValue(e);

MethodDecl _lift1(Function fun, Function wrapper) {
  final native = new NativeFunction((args) => wrapper(fun(args[0].value)));
  return new Method([], new FunctionCall(native, [new Self()]));
}

MethodDecl _lift2(Function fun, Function wrapper) {
  final native = new NativeFunction((args) =>
      wrapper(fun(args[0].value, args[1].value)));
  return new Method(["x"],
      new FunctionCall(native, [new Self(), new Variable("x")]));
}

Expression _bool(bool b) => new BoolLit(b);
Expression _num(num n) => new NumLit(n);
Expression _str(String s) => new StringLit(s);

final NUM_METHODS = {
  "+": _lift2((x, y) => x + y, _num),
  "-": _lift2((x, y) => x - y, _num),
  "*": _lift2((x, y) => x * y, _num),
  "/": _lift2((x, y) => x / y, _num),
  "%": _lift2((x, y) => x % y, _num),
  "~/": _lift2((x, y) => x ~/ y, _num),
  "<": _lift2((x, y) => x < y, _bool),
  "<=": _lift2((x, y) => x <= y, _bool),
  ">": _lift2((x, y) => x > y, _bool),
  ">=": _lift2((x, y) => x >= y, _bool),
  "==": _lift2((x, y) => x == y, _bool),
  "toString": _lift1((x) => x.toString(), _str),
};

final BOOL_METHODS = {
  "&&": _lift2((x, y) => x && y, _bool),
  "||": _lift2((x, y) => x || y, _bool),
  "==": _lift2((x, y) => x == y, _bool),
  "toString": _lift1((x) => x.toString(), _str),
};

final STRING_METHODS = {
  "+": _lift2((x, y) => x + y, _str),
  "==": _lift2((x, y) => x == y, _bool),
  "toString": _lift1((x) => x.toString(), _str),
};

void eval(Program program,
          void onLine(String line),
          void onError(Exception error)) {
  final interpreter = new Interpreter(program.clazzes);
  evalLet(PersistentMap<String, Value> env, LetPrintDecl let) {
    let.match(
      letprint: (name, expr, body) {
        final newEnv = env.insert(name,
            new RealValue(interpreter.eval(env, null, expr)));
        evalLet(newEnv, body);
      },
      print: (expressions) {
        for (final expr in expressions) {
          onLine(interpreter.eval(env, null, expr));
        }
      });
  }
  try {
    evalLet(EMPTY_ENV, program.let);
  } catch (e) {
    onError(e);
  }
}

PersistentMap<String, Value>
    _mkEnv(List<String> names, Iterable<Value> values) {
  final valueList = values.toList();
  var env = EMPTY_ENV;
  for (int i = 0; i < values.length; i++) {
    env = env.insert(names[i], valueList[i]);
  }
  return env;
}

class Interpreter {
  final PersistentMap<String, Clazz> clazzes;
  int varCounter = 0;

  Interpreter(this.clazzes);

  Map<String, int> counters = {};
  String genSym(String x) {
    int n = counters.putIfAbsent(x, () => 0);
    counters[x] = n+1;
    return "$x$n";
  }

  Clazz _lookupClazz(String name) {
    return clazzes.lookup(name).orElseCompute(() {
      throw "class $name not found";
    });
  }

  ExpressionOrMethod _lookup(Expression value, String name) {
    void complain(className) {
      throw "$name not found in class $className";
    }

    if (value is ConstructorCall) {
      final clazz = _lookupClazz(value.constructorName);
      final fieldIndex = clazz.fields.indexOf(name);
      if (fieldIndex != -1) {
        return new SomeExpression(value.arguments[fieldIndex]);
      } else {
        final method = clazz.methods.lookup(name);
        if (method.isDefined) {
          return new SomeMethod(method.value);
        } else {
          complain(clazz.name);
        }
      }
    } else if (value is NumLit) {
      final method = NUM_METHODS[name];
      if (method == null) complain("num");
      return new SomeMethod(method);
    } else if (value is BoolLit) {
      final method = BOOL_METHODS[name];
      if (method == null) complain("bool");
      return new SomeMethod(method);
    } else if (value is StringLit) {
      final method = STRING_METHODS[name];
      if (method == null) complain("string");
      return new SomeMethod(method);
    } else {
      throw "${pretty(value)} is not an object";
    }
  }

  static Value _lookupVariable(PersistentMap<String, Value> env, String x) {
    return env.lookup(x).orElseCompute(() {
      throw "variable $x not declared";
    });
  }

  Expression rebuild(int level,
                     PersistentMap<String, Value> env,
                     Expression self,
                     Expression expression) {
    return expression.match(
      self: () => self,
      constructorcall: (name, args) {
        final newArgs = args.map((a) => rebuild(level, env, self, a)).toList();
        return new ConstructorCall(name, newArgs);
      },
      variable: (x) {
        Option<Value> maybeValue = env.lookup(x);
        return (maybeValue.isDefined)
          ? maybeValue.value.match(
              symbolvalue: (y) => new Variable(y),
              realvalue: (v) => v)
          : new Variable(x);
      },
      lambda: (params, body) {
        final newParams = params.map((x) => genSym(x)).toList();
        final newEnv = env.union(_mkEnv(params, newParams.map(_symbolValue)));
        final newBody = rebuild(level, newEnv, self, body);
        return new Lambda(newParams, newBody);
      },
      let: (name, expr, body) {
         return rebuild(level, env, self,
            new FunctionCall(new Lambda([name], body), [expr]));
      },
      functioncall: (fun, args) {
        final newFun = rebuild(level, env, self, fun);
        final newArgs = args.map((a) => rebuild(level, env, self, a)).toList();
        return new FunctionCall(newFun, newArgs);
      },
      getsend: (receiver, name) {
        final newReceiver = rebuild(level, env, self, receiver);
        return new GetSend(newReceiver, name);
      },
      send: (receiver, name, args) {
        final newReceiver = rebuild(level, env, self, receiver);
        final newArgs = args.map((a) => rebuild(level, env, self, a)).toList();
        return new Send(newReceiver, name, newArgs);
      },
      ifthenelse: (cond, thenE, elseE) {
        final newCond = rebuild(level, env, self, cond);
        final newthenE = rebuild(level, env, self, thenE);
        final newElseE = rebuild(level, env, self, elseE);
        return new IfThenElse(newCond, newthenE, newElseE);
      },
      numlit: (n) => new NumLit(n),
      boollit: (b) => new BoolLit(b),
      stringlit: (s) => new StringLit(s),
      nativefunction: (f) => new NativeFunction(f),
      brackets: (expr) => new Brackets(rebuild(level + 1, env, self, expr)),
      lift: (expr) => new Lift(rebuild(level, env, self, expr)),
      escape: (expr) {
        if (level == 1) {
          final value = eval(env, self, expr);
          return value.match(
            brackets: (newExpr) => newExpr,
            otherwise: () { throw "cannot escape ${pretty(value)}"; });
        } else {
          return new Escape(rebuild(level - 1, env, self, expr));
        }
      },
      run: (expr) => new Run(rebuild(level, env, self, expr)));
  }

  Expression eval(PersistentMap<String, Value> env,
                  Expression self,
                  Expression expression) {
    return expression.match(
      self: () => self,
      constructorcall: (name, args) {
        // fail early
        final clazz = _lookupClazz(name);
        if (clazz.fields.length != args.length) {
          throw "wrong number of arguments for constructor $name";
        }
        // eval
        final argValues = args.map((a) => eval(env, self, a)).toList();
        return new ConstructorCall(name, argValues);
      },
      variable: (x) {
        Value value = _lookupVariable(env, x);
        return value.match(
          symbolvalue: (_) => throw "the impossible has happened",
          realvalue: (v) => v);
      },
      lambda: (params, body) {
        final newParams = params.map((x) => genSym(x)).toList();
        final newEnv = env.union(_mkEnv(params, newParams.map(_symbolValue)));
        final newBody = rebuild(1, newEnv, self, body);
        return new Lambda(newParams, newBody);
      },
      let: (name, expr, body) {
        return eval(env, self,
            new FunctionCall(new Lambda([name], body), [expr]));
      },
      functioncall: (fun, args) {
        final funValue = eval(env, self, fun);
        final argValues = args.map((a) => eval(env, self, a));
        return funValue.match(
          lambda: (params, body) {
            // fail early
            if (params.length != args.length) {
              throw "wrong number of arguments for ${pretty(fun)}";
            }
            // eval
            return eval(_mkEnv(params, argValues.map(_realValue)), null, body);
          },
          nativefunction: (f) => f(argValues.toList()),
          otherwise: () { throw "${pretty(funValue)} cannot be called"; }
        );
      },
      getsend: (receiver, name) {
        return _lookup(eval(env, self, receiver), name).match(
            someexpression: (expression) => expression,
            somemethod: (method) {
              final params = method.parameters;
              final args = params.map((x) => new Variable(x)).toList();
              return eval(env, self,
                  new Lambda(params, new Send(receiver, name, args)));
            });
      },
      send: (receiver, methodName, args) {
        final receiverValue = eval(env, self, receiver);
        final argValues = args.map((a) => eval(env, self, a)).toList();
        return _lookup(receiverValue, methodName).match(
            someexpression: (fun) {
              return eval(env, self, new FunctionCall(fun, argValues));
            },
            somemethod: (method) {
              final params = method.parameters;
              // fail early
              if (params.length != args.length) {
                throw "wrong number of arguments for method $methodName";
              }
              // eval
              return eval(_mkEnv(params, argValues.map(_realValue)),
                          receiverValue, method.body);
            });
      },
      ifthenelse: (cond, thenE, elseE) {
        final condValue = eval(env, self, cond);
        // fail early
        if (condValue is! BoolLit) {
          throw "expected a boolean";
        }
        // eval
        return condValue.value
            ? eval(env, self, thenE)
            : eval(env, self, elseE);
      },
      numlit: (n) => new NumLit(n),
      boollit: (b) => new BoolLit(b),
      stringlit: (s) => new StringLit(s),
      nativefunction: (f) => new NativeFunction(f),
      brackets: (expr) => new Brackets(rebuild(1, env, self, expr)),
      lift: (expr) =>
          new Brackets(rebuild(1, env, self, eval(env, self, expr))),
      escape: (expr) { throw "cannot escape at level 0"; },
      run: (expr) {
        final value = eval(env, self, expr);
        return value.match(
          brackets: (newExpr) => eval(EMPTY_ENV, null, newExpr),
          otherwise: () { throw "cannot run ${pretty(value)}"; });
      });
  }
}