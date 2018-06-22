# Voyager Notice Pre-processing

This tool preprocesses Voyager notice SIF files to email.  The intent is to handle these notices on the server without requiring manual runs of Voyager Reporter.

See a comparable process [autocirc from UTSA](https://github.com/cherveny/autocirc).  This was created rather than reusing autocirc because we are primarily interested in automating Item Available notices without additional python dependencies.

## Requirements

* Voyager 9 or later (Voyager 10 tested)
* Perl 5 or later (Perl 5.24 tested)
* Mojo::Template module for Perl
* Additional coding (currently work-in-progress)

## Installation

Drop this in an arbitrary directory accessible by the `voyager` user.

## Configuration

Edit the templates to customize your emails.  Note that the templates are named by notice type (e.g. circnotice type 01 is "circnotice/01.tmpl").

## Usage

Execute this as the `voyager` user, after the appropriate run of a cronjob created the notice file.  Pipe in the notice file, and write out the results of this application to the new notice file.  E.g.:
```
for n in $RPT_DIR/circnotice.*.inp; do mv $n $n.preprocess; perl circnotice.pl < $n.preprocess > $n; done
```

## Author / License

Written by Clinton Graham for the [University of Pittsburgh](http://www.pitt.edu).  Copyright (c) University of Pittsburgh.

Released under a license of GPL v2 or later.
