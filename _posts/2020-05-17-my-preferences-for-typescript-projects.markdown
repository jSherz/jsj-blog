---
layout: post
title: "My preferences for TypeScript projects"
date: 2020-05-17 18:13:00 +0100
categories:
  - TypeScript
  - Node.JS
  - Node
  - JavaScript
---

I have a number of preferences for [TypeScript] (TS) projects, built up from
seeing the language adopted by teams and drawing comparisons with other
ecosystems and strongly typed programing languages. These are mainly to do with
configuring the compiler on new projects and additionally general rules for how
you go about interacting with external data stores. I think TypeScript is a
great tool and offers a meaningful improvement over plain JavaScript, but you
only really get the most value out of it when you use it appropriately, and
invest time in learning it thoroughly.

[TypeScript]: https://www.typescriptlang.org

## Learning TypeScript

TypeScript is evolving very quickly. As a result, developers who have used it a
year or six months in the past may not have taken advantage of a lot of the
features that it now has to offer. Much of the great developer experience that
TS has to offer comes from the built in types, features of the type system and
safety checks that the compiler can perform, all of which are constantly
improving. A key part of TS adoption working well for you or for your team is
that developers are clued-up on the available language features and constantly
refresh their knowledge as new versions of the compiler are released.

A practical example of the need to learn the available language features are
type guards. If you're reading this article, I'm sure you know what they are and
how they're used. When writing plain JavaScript, you'll likely have written
functions or if statements that check for the shape of the object, but getting
into the habit of expressing these as type guards is important to avoid fighting
the type system and littering the code with `as` statements. The use of `as` and
not relying on type inference can make the language feel onerous to use and thus
harms the dev experience as well as the safety.

My recommendation would be to ensure that new team members read through the
official TS documentation and try setting up a small demo project before they
embark on using it to contribute to your projects. It's very easy to fall into
the trap of adding a few types here and there to normal JavaScript code and
therefore not take advantage of the available language features, many of which
are important to realise the safety TS can provide. As with any new language
learning, having feedback from more experienced developers in pull requests is
very helpful in ensuring language features get used appropriately and that their
knowledge stays up-to-date as the compiler changes. Having at least one person
in the team who's signed up to [the TypeScript Weekly newsletter] and is seeing
the features as they're released is super helpful to improve the team's
effectiveness with the language.

[the TypeScript Weekly newsletter]: https://www.typescript-weekly.com

## tsconfig.json

One of the key areas in getting value out of TS is to look closely at what
you're trying to achieve in using it, specifically why you think it gives you
value over plain JavaScript. While a lot of people think the primary value is
extra safety, we have to think about what that safety means and how the compiler
can help us achieve that. Understanding what options are available in the
tsconfig.json file is key to learning what checking the compiler can perform for
you and can help you achieve your goals of adopting the language.

The `tsc` utility will allow you to generate a new and heavily annotated
tsconfig.json file (run `tsc --init`). If any of the settings don't make sense,
check out the [tsconfig.json documentation]. I'd recommend that if you're the
engineering lead on a project, you take time to read through the available
options and setup a standardised config for your team's projects. Once engineers
have read through the [basic introduction to TypeScript], you can direct them to
the tsconfig documentation for more information about what the compiler is
capable of doing and to see examples of why certain errors will appear when
they're writing code. This is a huge help when they're learning the language and
will often be running into these errors if they're writing code that's
acceptable in plain JavaScript but viewed as unsafe with strict TS options
enabled.

[tsconfig.json documentation]: https://www.typescriptlang.org/tsconfig
[basic introduction to TypeScript]: https://www.typescriptlang.org/docs/handbook/typescript-in-5-minutes.html

As a general rule of thumb, I enable all the strictness related options and then
tailor the `target` (output language level) and `lib` (built-in features) to the
version of Node.JS that I'm using for the project. Investing effort in
configuration upfront will pay dividends later when you're trying to reap the
safety benefits of the language. Stricter or safer programming styles are harder
to retrofit if code is written without those options being enabled.

### Split tsconfig files

One technique that I learned from some colleagues recently relates to how you
have TS configured for the test and the source files. One of the problems that
you might have if you set up the tsconfig to build all the files that it can
find is that you end up building the source and test files (e.g. `src` and
`test`) into your distributed application. If you only want to publish the built
`src` folder or even have different configuration while you're writing the tests
themselves, having two tsconfig files enables this. Perhaps you'd like to turn
off the unused local variables error while you're writing the tests but still
want this check performed against the finished production code.

The main `tsconfig.json` file will be picked up by the editor and supporting
tools that you use and thus should cover your test and source files.

```json
{
  "compilerOptions": {
    "incremental": true,
    "target": "ES2018",
    "module": "commonjs",
    "lib": ["ES2018"],
    "declaration": true,
    "outDir": "./dist",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "esModuleInterop": true,
    "inlineSourceMap": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": [
    "src/**/*.ts",
    "test/**/*.ts"
  ]
}
```

The additional `tsconfig.build.json` file is used only for producing the built
code, e.g. when publishing a package or shipping a new version of the service. A
Yarn / NPM script with `tsconfig -p tsconfig.build.json` will select this file
when required.

```json
{
  "extends": "./tsconfig.json",
  "include": [
    "src/**/*.ts"
  ]
}
```

## Choosing libraries

Support for TS in the NodeJS ecosystem / MPM ecosystem is really strong and
improving constantly. I think we're very lucky that TS is gaining wide adoption
and typings are often included either in the library itself, or are in the
`@types` namespace on NPM. However, if you're starting a project from scratch,
it might be worth thinking about the libraries that you would normally use for
certain functions and then looking at the quality of the typings that are
provided with them. If you have a library that there are common alternatives to
(e.g. lodash has lots of competing libraries), it's worth checking that the
typings that come with that library or that are available (if they are
available) are of a high quality. What do I mean by a high quality? They should:

* cover all functions, classes and variables etc that the library exports;

    Check for the frequent use of `any` or `Object` to see areas where the
    typings are missing the requisite detail.

* be generic when the resulting type is dependent on an external system, data
  store or user provided value;

    For example the `AxiosResponse<T>` interface in the `axios` package lets you
    easily swap out the response type for the shape that will be returned by
    your API call.

* be up-to-date with the library itself.

If they're not of a high quality, you often end up fighting them by manually
overriding the typings as you're developing. This adds time to your development,
friction for your teammates and takes away some safety as it introduces the
possibility for error when asserting what type the variables or functions are.

Often you find that the typings are actually very good, and they cover pretty
much everything you need. If they don't, it's always worth seeing if you can
contribute back to them by making small fixes or improvements were possible
because helps the ecosystem as a whole.

## Dealing with external data stores

Libraries that deal with APIs, HTTP calls, data stores and other external
systems are another kettle of fish and present their own challenges. What good
is a TS library that retrieves rows from a PostgreSQL table if the type it
produces is `object[]`? Although we may have great type safety up to this point,
using the results of queries can be challenging as we're often left to assert
that they're of a given shape (e.g. an interface). If the data store changes, an
API version is released or we just make a mistake in the reproduction of those
types, we lose any safety that TS can offer. There are a few options to work
around this problem:

### Code generation

By far my favourite method of dealing with external systems is code generation,
in which the return types of method calls are automatically calculated from a
GraphQL schema, database schema, Elasticsearch mapping or similar. Some examples
of this include the [@graphql-codegen/typescript] and [ts-protoc-gen] libraries.
If you're looking to implement code generation and have access to a schema, you
can easily create TS typings with handlebars templates that loop through the
properties of the input objects and output relevant interfaces or types.

[@graphql-codegen/typescript]: https://graphql-code-generator.com/docs/plugins/typescript/
[ts-protoc-gen]: https://github.com/improbable-eng/ts-protoc-gen

### Validation

Manually validating the response from external system calls is much more time
consuming than using readily available code generation but may be a good option
when mature tools haven't been made for your target system. The [io-ts] library
ties the validation to the produced type and lets you assert that the response
you're given matches the shape that you expect.

[io-ts]: https://github.com/gcanti/io-ts

### Schema based types

A halfway house between code generation or validation and asserting that the
response is in a given shape is to define types that are based on the schema of
the data store. An example of this is by defining an interface with the shape of
an Elasticsearch mapping and then writing types that, given a query or
aggregation, will produce the output type of the system. This can be a fun
exercise if you're really into type theory or stretching the capabilities of the
compiler, but can leave you with complex typings that make your colleagues who
are newer to TS weep.

I've listed the above options in my order of preference. You have to weigh up
the time investment against the safety they can provide to find which one is the
right solution for you or your team.
