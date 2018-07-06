# Voyager Notice Pre-processing

This tool preprocesses Voyager notice SIF files to email.  The intent is to handle these notices on the server without requiring manual runs of Voyager Reporter.

See a comparable process [autocirc from UTSA](https://github.com/cherveny/autocirc).  This was created rather than reusing autocirc because we are primarily interested in automating Item Available notices without additional python dependencies.

## Requirements

* Voyager 9 or later (Voyager 10 tested)
* Perl 5 or later (Perl 5.24 tested)
* Perl modules:
  * Mojo::Template
  * Email::Sender
  * Email::MIME
  * HTML::FormatText or HTML::WikiConverter::Markdown (if using HTML templates for email)
* UTF-8 based email templates (sorry, too lazy to normalize UTF-8 Voyager data with another encoding)
* Additional coding (currently work-in-progress)

## Installation

Drop this in an arbitrary directory accessible by the `voyager` user.

## Configuration / Customization

Edit the templates to customize your emails.  Note that the templates are named by notice type (e.g. crcnotes type 01 is "crcnotes/01.tmpl").

The script uses a regular expression to identify whether the hostname contains the keyword "prod" to enable production email sending.  Otherwise, the script munges the email address.  This will need to be modified to your local hostname configurations and/or local test email domain.

## Usage

Execute this as the `voyager` user, after the appropriate run of a cronjob created the notice file.  Pipe in the notice file, and write out the results of this application to the new notice file.  E.g.:
```
for n in $RPT_DIR/crcnotes.*.inp; do mv $n $n.preprocess; perl crcnotes.pl < $n.preprocess > $n; done
```

## Author / License

Written by Clinton Graham for the [University of Pittsburgh](http://www.pitt.edu).  Copyright (c) University of Pittsburgh.

Released under a license of GPL v2 or later.
