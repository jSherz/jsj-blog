# jsj-blog

A collection of snippets, tips and reflections on what worked and more importantly, what didn't.

Proudly powered by [Jekyll](https://jekyllrb.com/).

## Read the blog

Unless you're a big fan of raw Markdown, you can view the blog at [https://jsherz.com](https://jsherz.com).

## Developing and publishing

Install rbenv and then Ruby version 3.1.2

```bash
rbenv install 3.1.2
```

To run a development server on port 4000, use:

```bash
bundle install
bundle exec jekyll serve
```

To build the assets ready to upload to your favourite CDN:

```bash
bundle exec jekyll build
```
