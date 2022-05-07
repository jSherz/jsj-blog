---
layout: post
title: "Starting a new project with a Pull Request (or Merge Request)"
date: 2022-05-07 17:33:00 +0100
categories:
  - git
  - GitHub
  - GitLab
  - Pull Request
  - Merge Request
---

When you start a new project in GitHub or GitLab as part of a team, it's easy
to just push the first version of the code to your trunk/main branch and then
be left with no easy way to create a Pull Request or Merge Request that is an
accurate view of your changes. This makes it harder for colleagues to comment
on specific parts of the code, and for you to test the CI/CD that runs on
branches.

To avoid this, start by committing everything that you've worked on:

```
git add -A .
git commit -a -m "my lovely work, v0.1"
```

Rename your current trunk/main branch, assuming it's called `main`:

```
git branch -m my-feature-branch
```

Then create a fresh new `main` with no commits:

```
git checkout --orphan main
git rm -rf .
```

Create an empty initial commit:

```
git commit --allow-empty -m "initial commit"
```

**DANGER:** Now we're going to forcefully push up the new empty branch,
overwriting what is already in our remote. Bookmark https://ohshitgit.com if
you're so inclined. Worse case scenario, it's always faster to write the second
time, right?!

```
git push -f --set-upstream origin main
```

Switch over to the feature branch you renamed above:

```
git reset --hard HEAD
git checkout my-feature-branch
```

Rebase it onto your new, empty, `main` branch:

```
git rebase main
```

And push ready for a Pull or Merge Request:

```
git push --set-upstream origin my-feature-branch
```

## What if I want to avoid this pain next time?

Create a folder for your new project, initialise git and then create your first
commit:

```
git init
git commit --allow-empty -m "initial commit"
```

Then start a feature branch:

```
git checkout -b my-feature-branch
```

Much easier!

## References

* https://gist.github.com/ozh/4734410
