---
layout: post
title: "Debugging TypeScript/JavaScript CDK projects - a few tips and tricks"
date: 2023-02-26 16:14:00 +0000
categories:

- AWS
- CDK
- Node.JS
- TypeScript

---

When I moved to the Node.js ecosystem from working in Java, I was struck by how
hard it was to get a working debugger. In Java or C#, I'd hit a button in the
IDE and get perfect registration of breakpoints without any configuration. In
Node, the story was not the same! Things have improved dramatically over the
last ~5 years I've been working day-to-day in JavaScript/TypeScript, so let's
have a quick review of the basics and then talk about CDK specific tips.

## Making the most of your editor

A lot of IDEs will offer you the option to save some configurations for
starting your application, including with the option to debug it. If that works
for you, skip the pain of manual setup and use the editor to launch your code
while you're developing it.

If you've not yet tried the debugger support in your editor, it's worth both
trying to have it launch the application and also exploring the options to
attach to an existing, running, process. I reckon I'm about 3-5x faster
debugging with a proper debugger over printing console output to the screen,
so it's something I teach any Node developer I work with whose not used it
before. An additional gotcha is that the stringification of values can hide
useful information if you use the console vs being able to inspect the full
object or class in a debugger.

## Starting a Node process with debugging

Node offers us two flags that are useful for debugging: `--inspect` and
`--inspect-brk`. I prefer the latter as both start a server to connect a
debugger, but only the latter pauses the execution of your program until the
debugger has connected.

If your code is already transpiled, you can go right ahead with:

```bash
node --inspect-brk src/my-file.js
```

Otherwise, you might wish to build it first:

```bash
yarn build # or npm run build
node --inspect-brk dist/my-file.js
```

Perhaps you prefer to have [ts-node] transpile it at the time of use:

```bash
node --inspect-brk --require ts-node/register src/my-file.ts
```

[ts-node]: https://www.npmjs.com/package/ts-node

If you are writing TypeScript, I recommend enabling the `inlineSourceMap`
compiler option in your `tsconfig.json` - I've had better success getting
external tooling like debuggers to pick up inline source maps over separate
`.map` files.

Regardless of the method you chose to start your application with debugging,
you'll see the following output in the console and your program will not start:

```
Debugger listening on ws://127.0.0.1:9229/065d3f49-c2b9-4657-a354-31f8b0f1c39f
For help, see: https://nodejs.org/en/docs/inspector
```

Attach your debugger, e.g. the one in your IDE, and start setting breakpoints!

### Guides for editor configuration

* [WebStorm - Debug code](https://www.jetbrains.com/help/webstorm/debugging-code.html)
* [VSCode - Debugging in Visual Studio Code](https://code.visualstudio.com/docs/editor/debugging)
* [Node.js - Debugging - Getting Started](https://nodejs.org/en/docs/guides/debugging-getting-started/)

## Attaching to an existing process

We can additionally attach to an existing Node process by sending it the
`SIGUSR1` signal. This works for long-running processes, but isn't really
applicable for us in our use of CDK.

```bash
# Find your process' ID
ps aux | grep node

# Send it the USR1 signal
kill -USR1 <process ID> # e.g. kill -USR1 123456789
```

## Debugging our CDK applications written in TypeScript

These steps will be the same or very similar for JavaScript CDK projects, but
we're going to be focusing on TypeScript projects as they have an extra layer
of complexity with the code being transpiled.

When CDK runs your code, it doesn't run in the same process. In fact, there may
be a number of processes at work. You might run your CDK app as follows:

```bash
yarn cdk deploy

# or

npx --no cdk deploy
```

**NB:** if you've never used the poorly named `--no` flag with npx, it stops
npx downloading the package before it's used. I believe this should be your
default when you're working inside a project - you should use a locally
specified dependency, not whichever version gets installed at the time the
command is run. I've seen a tonne of CI pipelines written with npx and a lack
of `--no` option - it always ends in tears!

Yarn, npx or NPM start initially and then load their configuration and your
code. Let's make a JavaScript file that does nothing but sits open:

_run-and-wait.js_
```javascript
setTimeout(() => {}, 1000 * 60 * 60);
```

We'll then add a package.json entry for it:

```json
{
  "name": "...",
  "scripts": {
    "run-and-wait": "node run-and-wait.js"
  }
}
```

Let's run it with Yarn and observe the process tree that's created:

```bash
# Find the process ID
ps aux | grep node

# Output the tree
pstree 37554
```

I've included the parent shell that's running our `node` command here just for
interest. We could easily have run `pstree 38033` to just see the Node bit.

```
-+= 37554 jsj /bin/zsh --login -i
 \-+= 38033 jsj node /snipped/node18/bin/yarn run-and-wait
   \--- 38034 jsj /snipped/node18/bin/node run-and-wait.js
```

So which one of these do we send a `SIGUSR1` to when we're debugging? We want
the process which is actually running our code, not that one that launched it.
We'd run `kill -USR1 38034`. I always think of it in terms of the process
that's showing up as the command `node` followed by a file that's part of my
project, not the node_modules or centrally installed packages.

Let's have a look at some real CDK process trees when run in different ways:

```
yarn cdk deploy
```

```
-+= 37554 jsj /bin/zsh --login -i
 \-+= 39727 jsj node /snipped/node18/bin/yarn cdk deploy
   \-+- 39730 jsj /snipped/node18/bin/node /projects/cdk-debugging/node_modules/aws-cdk/bin/cdk deploy
     \-+- 39739 jsj npm exec ts-node -P tsconfig.json --prefer-ts-exts bin/cdk-debugging.ts
       \--- 39757 jsj /snipped/node18/bin/node /projects/cdk-debugging/node_modules/.bin/ts-node -P tsconfig.json --prefer-ts-exts bin/cdk-debugging.ts
```

Four processes! We have an interesting crossover because we've opted to use
yarn as our package manager, but the default cdk.json comes with a use of npx.

```
npm run cdk:deploy
```

```
\-+= 37554 jsj /bin/zsh --login -i
  \-+= 39908 jsj npm run cdk:deploy
    \-+- 39912 jsj node /projects/cdk-debugging/node_modules/.bin/cdk deploy
      \-+- 39914 jsj npm exec ts-node -P tsconfig.json --prefer-ts-exts bin/cdk-debugging.ts
        \--- 39915 jsj node /projects/cdk-debugging/node_modules/.bin/ts-node -P tsconfig.json --prefer-ts-exts bin/cdk-debugging.ts
```

A different line-up, but still four processes excluding our shell.

```
npx --no cdk deploy
```

```
-+= 37554 jsj /bin/zsh --login -i
 \-+= 39977 jsj npm exec cdk deploy
   \-+- 39987 jsj node /projects/cdk-debugging/node_modules/.bin/cdk deploy
     \-+- 40006 jsj npm exec ts-node -P tsconfig.json --prefer-ts-exts bin/cdk-debugging.ts
       \--- 40007 jsj node /projects/cdk-debugging/node_modules/.bin/ts-node -P tsconfig.json --prefer-ts-exts bin/cdk-debugging.ts
```

In all of the above cases, we've got a series of processes being created to get
to the nuts and bolts of running our code. If we want to add an `--inspect-brk`
option, we have to ensure that it's getting to the bottom layer. If you're a
lot faster on the terminal than me, you might be able to pull off a quick
`USR1` signal before the interpreter gets to the code you're interested in,
but I find it much easier to have the time to get my debugger connected. That's
why I reach for `--inspect-brk` over just `--inspect` - I don't want it to be a 
race to get debugging.

Let's tweak our `cdk.json` to add that option:

```json
{
  "app": "ts-node --inspect-brk -P tsconfig.json --prefer-ts-exts bin/cdk-debugging.ts"
}
```

Does that work? Absolutely not!

```
/projects/cdk-debugging/node_modules/arg/index.js:90
                                                throw err;
                                                ^

Error: Unknown or unexpected option: --inspect-brk
    at arg (/projects/cdk-debugging/node_modules/arg/index.js:88:19)
    at parseArgv (/projects/cdk-debugging/node_modules/ts-node/dist/bin.js:69:12)
```

OK, so ts-node doesn't support the `--inspect-brk` flag, so what do we do? In
the process trees above, you can see that ts-node exists in the .bin folder in
the node_modules folder of our project. We can swap out the call to ts-node
with the full path and the raw node command:

_cdk.json_
```json
{
  "app": "node --inspect-brk node_modules/.bin/ts-node -P tsconfig.json --prefer-ts-exts bin/cdk-debugging.ts"
}
```

```bash
yarn cdk deploy
```

```
Debugger listening on ws://127.0.0.1:9229/252705b1-c9f7-4178-8315-731fc56a5f41
For help, see: https://nodejs.org/en/docs/inspector
```

Success! Now we can launch our debugger and get cracking.

## A node_modules related gotcha

If setting a breakpoint in a package isn't working, inspect your `yarn.lock`
or `package-lock.json` to check if multiple copies of the same package are
installed. You might find that you've set a breakpoint in the wrong one. If 
you're trying to set a breakpoint near a `throw` statement, double check that
the file you're looking at is the one mentioned in stack trace of the error 
you're hunting down.

## A source-map-support gotcha

If you're in a codebase that's transpiled, I highly recommend the use of a
package that shows you error stack traces in the file names and line numbers of
the source language. For example, you might use [source-map-support],
[@cspotcode/source-map-support] or [source-map-loader]. They turn a stack
trace that looks like this:

```
/projects/cdk-debugging/lib/cdk-debugging-stack.js:10
        throw new Error("hello, world");
        ^

Error: hello, world
    at new CdkDebuggingStack (/projects/cdk-debugging/lib/cdk-debugging-stack.js:10:15)
    at Object.<anonymous> (/projects/cdk-debugging/bin/cdk-debugging.js:9:15)
```

Into one that looks like this:

```
/projects/cdk-debugging/lib/cdk-debugging-stack.ts:14
    throw new Error("hello, world");
          ^
Error: hello, world
    at new CdkDebuggingStack (/projects/cdk-debugging/lib/cdk-debugging-stack.ts:14:11)
    at Object.<anonymous> (/projects/cdk-debugging/bin/cdk-debugging.ts:10:15)
```

Super helpful! A downside of these packages in our context of debugging and
breakpoint setting is that it may obscure the location of the JavaScript code
that you're trying to inspect. In most cases, my IDE of choice (WebStorm) has
managed to find the right JavaScript when I've added breakpoints to the
TypeScript source code. When that fails, I've been able to hunt down the
right line of JavaScript by compiling the project upfront (as opposed to the
use of ts-node) and comparing the source and generated `.js` file. At worst,
I've gone for a bit of a scatter-gun approach with plenty of breakpoints in the
affected area that I can whittle down later.

[source-map-support]: https://www.npmjs.com/package/source-map-support
[source-map-loader]: https://www.npmjs.com/package/source-map-loader
[@cspotcode/source-map-support]: https://www.npmjs.com/package/@cspotcode/source-map-support

## An aws-cdk gotcha

We've got one final gotcha on our CDK debugging journey: the aws-cdk package.
Let's trigger an error in that package by adding a lookup to an AMI that
doesn't exist. The filters parameter of [the DescribeImages API] can be a bit
of a pain to get right, so perhaps we want to inspect exactly what's being
passed to the AWS SDK by CDK.

[the DescribeImages API]: https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_DescribeImages.html

```typescript
const ami = new aws_ec2.LookupMachineImage({
    name: "blah",
    owners: ["123456789012"],
    windows: false,
});

new CfnOutput(this, "DummyAmiId", {
    value: ami.getImage(this).imageId,
});
```

That shows the following error:

```
Searching for AMI in 123456789012:eu-west-1
[Error at /cdk-debugging] No AMI found that matched the search criteria

Found errors
```

If we do a search in files in our node_modules, we'll get some matches for the
above error text of "No AMI found that matched the search criteria":

```bash
grep -re "No AMI found that matched the search criteria" node_modules
```

```
node_modules/aws-cdk/lib/context-providers/ami.js: throw new Error('No AMI found that matched the search criteria');
node_modules/aws-cdk/lib/index.js: ... huge unreadable blob ...
node_modules/aws-cdk/lib/index.js.map: ... huge unreadable blob ...
```

I used grep as, when I first attempted to find the file to set a breakpoint, my
editor refused to search in the index.js and index.js.map as they're too big.
This is where we encounter the footgun in the aws-cdk package - it contains two
copies of the code: one as the raw files and one as a huge bundled index.js.

Trying to set a breakpoint in the twenty-odd megabyte minified index.js that
actually gets run is near impossible. I spent a good couple of hours scratching
my head recently trying to work out why my breakpoint in the equivalent of the
context-providers/ami.js file wasn't getting hit.

### Workarounds

One option is to wade your way through the minified code and whack a debugger
statement in there:

```javascript
if(images.length===0){throw new Error("No AMI found that matched the search criteria")}
```

Becomes:

```javascript
if(images.length===0){debugger;throw new Error("No AMI found that matched the search criteria")}
```

Then begins the challenge of having your debugger/editor stop in the file and
not crash. I hate to say it, but unless you're sitting on a machine with bags
of memory, I'd replace that `debugger` statement with a `console.log` and try
to spend as little time debugging in aws-cdk as possible. How hypocritical!

## Conclusion

As with many other areas of JavaScript/TypeScript development, debugging in CDK
projects is still harder than it should be. I hope these tips help! If you're a
bit of a debugging guru and a colleague asks for help with their whopping stack
of console.logs, share the love and show them why a "proper" debugger can
save them a whole heap of time.
