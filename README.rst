Note about this branch
======================

This branch built the PHP7.0, PHP7.1 and PHP7.2 on https://lewiscowles1986.github.io/experiments/wasm/php/

It does not contain the HTML, or JS; both were borrowed from PHP.net to get a boilerplate up and running.

It's quite likely I'm going to leave this where it is, as I only require a REPL, 
with very limited PHP extensions.

My Scope is smaller than Derick Rethans, the original author of this repo. In-fact XML is missing compared to the 8.x

I also do not plan to integrate all the branches. For me the fact the artifact,
has a common interface is enough for now.

If you build something cool, please let me know.

PHP WASM Builder
================

The Dockerfile in this repository builds the PHP WASM files for use in the
documentation, and the PHP Tour.

You can build them, by running the following command::

	docker buildx bake

The builds will then up in the ``build/`` directory. These two files then need
to be copied to https://github.com/php/web-php.git/js (as ``php-web.wasm`` and
``php-web.mjs``)

By default, this will build PHP 8.4.3, but you can override this by setting an
argument::

	docker buildx bake --set default.args.PHP_VERSION=8.3.16

Supported Extensions
--------------------

- Core
- calendar
- ctype
- date
- dom
- hash
- json
- libxml
- mbstring
- pcre
- random
- Reflection
- SimpleXML
- SPL
- standard
- xml
- xmlreader
