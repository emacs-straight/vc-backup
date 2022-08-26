vc-backup
=========

Find here the source for vc-backup.el, a [VC][VC] backend that uses
[Emacs backup files] for single-file version control.

[Emacs backup files]:
	https://www.gnu.org/software/emacs/manual/html_node/emacs/Backup.html
[VC]:
	https://www.gnu.org/software/emacs/manual/html_node/emacs/Version-Control.html

Installation
------------

`vc-backup` is available from [GNU ELPA]. It can be installed by
invoking

	M-x package-install RET vc-backup RET

[GNU ELPA]:
	http://elpa.gnu.org/packages/vc-backup.html

Usage
-----

`vc-backup.el` enables itself automatically via autoloading. It is
recommended to enable `version-control` so as to have multiple
versions of a file accessible. Increasing `kept-new-versions` makes
sure you have more versions to compare.

Contribute
----------

As `vc-backup+.el` is distribed as part of [GNU ELPA], and therefore
requires a [copyright assignment] to the [FSF], for all non-trivial
code contributions.

[copyright assignment]:
	https://www.gnu.org/software/emacs/manual/html_node/emacs/Copyright-Assignment.html
[FSF]:
	https://www.fsf.org/

Source code
-----------

`vc-backup` is developed on [SourceHut].

[SourceHut]:
	https://sr.ht/~pkal/vc-backup

Bugs and Patches
----------------

Bugs, patches, comments or questions can be submitted to my [public
inbox].

[public inbox]:
	https://lists.sr.ht/~pkal/public-inbox

Distribution
------------

vc-backup.el and all other source files in this directory are
distributed under the [GNU Public License], Version 3 (like Emacs
itself).

[GNU Public License]:
	https://www.gnu.org/licenses/gpl-3.0.en.html
