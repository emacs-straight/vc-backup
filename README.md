vc-backup
=========

vc-backup is a [vc][vc] backend that uses backups for single-file
version control.

Installation
------------

`vc-backup.el` is part of [GNU ELPA][elpa], and can be installed using
`package.el`.

Usage
-----

`vc-backup.el` enables itself automatically via autoloading. It is
recommended to enable `version-control` so as to have multiple
versions of a file accessible. Increasing `kept-new-versions` makes
sure you have more versions to compare.

Bugs
----

Bugs or patches can be submitted to my [public inbox][mail].  Note
that non-trivial contributions require a [copyright assignment][ca] to
the FSF.

This package is still young, so wishes, impressions and criticism are
very appreciated. If you have anything to say, feel free to send an
email to the aforementioned [public inbox][mail].

Copying
-------

`vc-backup.el` is distributed under the [GPL v3][gpl3] license.

[vc]: https://www.gnu.org/software/emacs/manual/html_node/emacs/Version-Control.html
[elpa]: http://elpa.gnu.org/packages/vc-backup.html
[setup]: http://elpa.gnu.org/packages/setup.html
[mail]: https://lists.sr.ht/~pkal/public-inbox
[ca]: https://www.gnu.org/software/emacs/manual/html_node/emacs/Copyright-Assignment.html#Copyright-Assignment
[gpl3]: https://www.gnu.org/licenses/gpl-3.0.en.html
