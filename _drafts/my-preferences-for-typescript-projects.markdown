---
layout: post
title: "My preferences for TypeScript project"
date: 2020-05-16 12:48:00 +0100
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
only really get the most value out of it when you use it appropriately, and if
you don't, then you get the illusion of safety but actually the safety's not
there.

[TypeScript]: https://www.typescriptlang.org

## Learning TypeScript

TypeScript is evolving very quickly. As a result, developers who have had
experience with it a year or six months in the past may not have taken advantage
of a lot of the features that it now has to offer. Much of the great developer
experience that TS has to offer comes from the built in types, features of the
type system and safety checks that the compiler can perform, all of which are
constantly improving. A key part of TS adoption working well for you or for your
team, is that developers are clued-up on the available language features and
constantly refresh their knowledge as new versions of the compiler are released.

Also, they know the features of the type system and how to use it really
effectively. If they don't, they're on that writing effectively JavaScript code
with a few types attached here and there. Or they try and fight the type system
because it won't do quite what they want. And they don't take full advantage of
the features that are available to get the maximum kind of safety. So, for
example, if you have a team member that doesn't know what type guards are, what
hasn't used them, they might be tempted to do a similar function manually or use
a lot of the as keyword Teo, declare that this object or variable, is of a
certain type, and the more you get away from actually checking things before use
thumb, the more you lose the safety Bunches that typescript can bring. It might
not be necessary if you two do specific training on typescript for the team,
because the documentation for the language features is excellent. But it's worth
at least one person in team keeping an eye on the typescript releases as they
come out and making sure that people are aware ofthe the features that are
available on DH. That you've got a strong knowledge of typescript in the team so
that when you go through pull requests, you can pick out areas where the
language hasn't been used effectively on DH, where a bit of education could help
a lot if your engineers ah, very skilled in typescript and using it really
effectively, they get the most value out of it. If they're writing job script
with a few types listed in are engaging in the typescript ecosystem on DH,
learning how to use it properly, they're likely see it as something that's
fighting them, something that is a potentially negative addition to the normal
coding they do in JavaScript.

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
to retrofit if the code is written without those options being enabled.

### Split tsconfig files

One technique that I learned from some colleagues recently relates to how you
have TS configured for the test files and the source files. One of the problems
that you might have if you set up the tsconfig to build all the files that it
can find is that you end up building the source and test files into your
distributed application, and that might be fine. That might be, in fact, what
you want. You want wanted to ship the tests in JavaScript so that you can run
them in JavaScript and verify that behaviour is correct. But you may just want
to export the source themselves. You may also want slightly less strict rules
while you're writing the tests themselves, perhaps around unused variables, for
example, which could get a little bit frustrating way writing tests. But then,
when you do the final build of the code into JavaScript in the continuous
integration environment, you perhaps want stricter settings to be applied. So
having two tears come thick files One of them, which has the default name T s
conflict Jason, and so is picked up by editors. For example, I'm one of them,
which is used explicitly when you want to do the build of the code for
deployment. If you use to custom names or have the tears come thick file that
deals with your test scripts, for example, and not be tears conflict that Jason
for name something else than what you can end up with happening is the editor
you're using won't apply the correct type checking rules to the test files as
you edit them. And so either they look like they're fine and the building okay,
but they won't build. Okay, when you then go to run the tests or run the final
build. Um

## Choosing libraries

the library. Support for typescript in the Know Jesse Ecosystem or the MPM
ecosystem is really strong and improving constantly. I think we're very lucky
that type scripts gaining wide adoption on the type things are very often either
included in the library themselves, or they are in the at types names based on
MPM. However, if you're starting a project from scratch, it might be worth
thinking about the libraries that you would normally use for certain functions
and then looking at the quality of the type things that are provided with them
if you have a library that they're common alternatives to. For example, Low Dash
has lots of competing libraries in them, different styles, but they do the same
thing will provide same sort of functions. It's worth checking that the type
things that come with that library or that are available if they are available.
Ah, a high quality. If they're not of a high quality, you often end up fighting
them on manually, overriding what the typing Zara's you're developing. And this
is then throwing away a lot of the ease of development, so damaging your develop
experience and also taking away some of the safety by your engineers having toe
say that this is a specific type, even when it's something else. Very often, you
find that the typing is actually very good, and they cover pretty much
everything you need. And if they don't, it's always worth seeing if you can
contribute back to them by making small fixes for improvements were possible
because that then helps the ecosystem in general, on future engineers that are
writing projects and typescript can. Then how have the advantage of your efforts
the data storage, live data access libraries in general struggle because they
don't know what the type of the data coming back from your system is going to
be. We'll take, for example, on elastic search query where the output of the
query is based upon the mapping or the scheme, a definition that you've got
defined in your in your data store. It is actually possible given on the last
exit query Onda mapping for Elastic Search Index to work out what the type will
be, um, once once the queries run. But this kind of type checking could be very
challenging, too, right, because the type that's returned by the service for
example, elastic search might be recursive, and it might require really good
knowledge off any type of query that could be run against the, um, data store
itself. If you want to avoid some of this complexity and producing type things
for these libraries, you might want to consider a data storage or validation
library that is typescript centric and thus aims to have as much safety as
possible by either generating the types for you or ensuring that the type that's
produced is much, very closely to the validation in case of I. B. S.

## Dealing with external data stores

one of the most challenging things to do with typescript can be interfacing with
external dates, stores or external systems in a type Safeway. A lot of what
normally happens is that you end up using some kind of library that works very
well in JavaScript but doesn't necessarily work particularly, well typescript.
And so the, um, type things associated with the library might give you the
general shape off the response. Perhaps you run a query against elasticsearch
on. Do you get the search results back is a field, but then the actual actual
data itself. That's the shape of the data that that query will produce often
isn't in back in the in the typing itself. So if you've got a table in a day,
space on the tables got to string columns and ah number column the shape of the
day to get back would probably be something like a list of objects, each of them
with two keys off number and ah, keys of a string. When you then move those
types around application as you manipulate the day, sir, what you end up with is
a lot of manual process to make sure that the types that coming out of the ah
Queary or interaction with an external system, and then the types that deal with
you know, your business logical, that has a case of processed and really rely on
those on those initial type things being right. Those type things that come out
day store, there might be certain things that you want to represent in that
response. So perhaps you've got some columns in your data store. Andi, they are
Mila ble if you got a relational database, and so you're database library, for
example, might always return a key in the objects that it makes for each, um,
column in the day in a day space table. But the, um, but the field the key value
will either be no or or say string or number whatever, but it will never be
undefined. And so the type that you want that object key tohave is really know
all the type that it is in the day space, and ideally, you don't want to have to
update the types in your application when the day space changes. There's a
couple of problems with relying on that. The first on, obviously, is that if you
forget to make the change in one place. So if you make a change the spacing Nazi
application, then it's out. Date. Andi. The type safety is lost in the
application near the cases that you are likely to have some kind of user error
and making those type things. So, for example, you might choose to say, OK, the
body that's gonna come back from this query is a string or number, but in
reality, the type of the day space might be different. Simon Day space could
just be another type, completely like a Boolean. Or perhaps there's some other
kind of subtle difference. So, for example, you might say, Oh, well, this field
is, you know, string. But it's actually optional. It might not be present,
whereas the database library perhaps only returns a, um ah, a string like the
column type or a no. If it only returns thing or annul, you might have a
checking application to test if it's undefined, because typescript will say,
Okay, this is a string or undefined. But then, actually, that that check might
fail that, you know, you might think that it's gonna be in the defined value or
string. So your tests probably haven't undefined value or string and your geared
up for that to be the case. But that's actually not the reality of days type of
getting back how to work around this. So I really heavily leaned towards
cogeneration when possible. There a few caveats. A cogeneration. The 1st 1 is
that if you don't already have the system to do it, so if you're adopting
typescript completely from scratch, it's very time consuming to write your own
cogeneration tools. If you can't find ones that fit the bill, and we'll cover
some techniques to alleviate that problem, but in general it still it still
expending effort. Effectively do. The sign into it is that, um, right in the
cogeneration tools, as with any other piece of software, has the ability Teoh
introduce bugs, and it requires a really good understanding off the library.
You've got the library's you've got on the type of data that's gonna come back
from them because the difference in a field psyche and objects not being
returned or the value being null then changed the type things, and they're
subtle things like that that are a bit of a pain. Teoh. Try and work out and to
know about. So you have to have good knowledge off the data store, the day
structures that nothing to build them. However, you can find that there are some
existing tooling options for doing those kind of types. So, for example, if you
got an open 80 I spec definition for on a P I, you're dealing with you
congenital rate client and server type ings based on that and a similar example
that's been easy to get going with is if you got an A P I or similar, uh,
schemer. So, for example, a graphic ul schema full on FBI. Then what you can do
is, um, you can use, um, handlebars, templates and then some kind of code
formatting to, like, prettier. And it's not the most sophisticated code
generation in the world on get certain like a pretty foolproof, and there are
limitations to using template ing languages. But what it gives you a way of
taking some kind of objects in tax tea tree or a P I definition and turning
into, um, unusable set of type things and actually the return on investment for
that set a return on investment for very simple handlebars. Templates with, um
typescript code in them is certainly a lot easier than, uh, trying to build up
the abstracts in text tree off the code you actually want on about putting that
as some kind of source code or rising typescript empire plug ins.

### Examples of code generation


