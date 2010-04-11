package RDF::TrineShortcuts;

=head1 NAME

RDF::TrineShortcuts - totally unauthorised module for cheats and charlatans

=head1 VERSION

0.07

=head1 SYNOPSIS

  use RDF::TrineShortcuts;
  
  my $model = rdf_parse('http://example.com/data.rdf');
  my $query = 'ASK WHERE {?person a <http://xmlns.com/foaf/0.1/Person>}';
  if (rdf_query($query, $model))
  {
    print "Document describes a person.\n";
  }
  else
  {
    print "Document doesn't describe a person.\n";
    print "What does it describe? Let's see...\n";
    print rdf_string($model);
  }

=cut

use strict;
use 5.008;

use Exporter;
use RDF::Trine '0.116';
use RDF::Trine::Serializer;
use RDF::Query '2.200';
use RDF::Query::Client;
use URI;
use URI::file;

our @ISA      = qw(Exporter);
our %EXPORT_TAGS = (
	default => [qw(rdf_parse rdf_string rdf_query)],
	nodes   => [qw(rdf_node rdf_literal rdf_blank rdf_resource)],
	all     => [qw(rdf_parse rdf_string rdf_query rdf_node rdf_literal rdf_blank rdf_resource rdf_statement)],
	);
our @EXPORT    = ( @{ $EXPORT_TAGS{'default'} } );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our $VERSION   = '0.07';
my $Has;

BEGIN
{
	$Has = {};
	foreach my $package (qw(XML::Atom::OWL HTTP::Link::Parser XRD::Parser RDF::RDFa::Parser))
	{
		$@ = undef;
		eval "use $package;";
		$Has->{$package} = 1 unless $@;
	}
}

=head1 DESCRIPTION

This module exports four functions which simplify frequently performed 
tasks using L<RDF::Trine> and L<RDF::Query>.

In addition, because it calls "use RDF::Trine", "use RDF::Query", and
"use RDF::Query::Client", your code doesn't need to.

=over 4

=item C<< rdf_parse($data) >>

$data can be some serialised RDF (in RDF/XML, Turtle, RDF/JSON, or any 
other format that L<RDF::Trine::Parser> supports); or a URI (string or 
L<URI> object); or an L<HTTP::Message> object; or a hashref (as per 
RDF::Trine::Model's add_hashref method); or a file name or an open file 
handle; or an L<RDF::Trine::Iterator::Graph>. Essentially it could be 
anything you could reasonably expect to grab RDF from. It can be undef.

The function returns an L<RDF::Trine::Model>.

There are additional optional named arguments, of which the two most 
useful are probably 'base', which sets the base URI for any relative URI 
references; and 'type', which indicates the media type of the input 
(though the function can usually guess this quite reliably).

  $model = rdf_parse($input,
                     'base' => 'http://example.com/',
                     'type' => 'application/rdf+xml');

Other named arguments include 'model' to provide an existing 
L<RDF::Trine::Model> to add statements to; and 'context' for providing a 
context/graph URI (which may be a string, URI object or RDF::Trine::Node).

=cut

sub rdf_parse
{
	my $input = shift;
	my %args  = @_;

	my $model   = $args{'model'} || RDF::Trine::Model->temporary_model;
	my $context = $args{'context'};
	my $type    = $args{'type'};
	my $base    = $args{'base'};

	return $model unless defined $input;

	if (defined $context and !ref $context)
	{
		if ($context =~ /^_:(.+)$/)
		{
			$context = RDF::Trine::Node::Blank->new($1);
		}
		else
		{
			$context = RDF::Trine::Node::Resource->new($context);
		}
	}
	elsif (UNIVERSAL::isa($context, 'URI'))
	{
		$context = RDF::Trine::Node::Resource->new("$context");
	}
	
	if ($input =~ /^([A-Za-z0-9_]+)(\;[^\r\n]*)?$/
        && UNIVERSAL::isa("RDF::Trine::Store::$1", "RDF::Trine::Store"))
	{
		die "need RDF::Trine 0.118 (for new_with_string support)"
			unless RDF::Trine::Store->can('new_with_string');
		
		$input = RDF::Trine::Store->new_with_string($input);
	}

	if (UNIVERSAL::isa($input, 'RDF::Trine::Store'))
	{
		$input = RDF::Trine::Model->new($input);
	}

	if (UNIVERSAL::isa($input, 'RDF::Trine::Model'))
	{
		$input = $input->as_stream;
	}

	if (UNIVERSAL::isa($input, 'RDF::Trine::Iterator'))
	{
		while (my $st = $input->next)
		{
			$model->add_statement($st, $context);
		}
		return $model;
	}

	if (ref $input eq 'HASH')
	{
		$model->add_hashref($input);
		return $model;
	}

	if (UNIVERSAL::isa($input, 'URI')
	or  $input =~ m'^(https?|ftp|file):\S+$')
	{
		my $accept = 'application/rdf+xml, text/turtle, application/json;q=0.1, application/xhtml+xml;q=0.1';
		$accept .= ', application/atom+xml;q=0.2' if $Has->{'XML::Atom::OWL'};
		$accept .= ', application/xrd+xml;q=0.2'  if $Has->{'XRD::Parser'};
		
		my $ua = LWP::UserAgent->new;
		$ua->agent(sprintf('%s/%s ', __PACKAGE__, $VERSION));
		$ua->default_header("Accept" => $accept);

		$input = $ua->get("$input");
	}

	if (UNIVERSAL::isa($input, 'HTTP::Message'))
	{
		$type  = $input->content_type unless defined $type;
		$base  = $input->base;
		$input = $input->decoded_content;
		
		unless ($args{'no_http_links'} || !$Has->{'HTTP::Link::Parser'})
		{
			parse_links_into_model($input, $model);
		}
	}

	if ($input !~ /[\r\n\t]/ and -e $input)
	{
		my $fn = $input;
		$input = undef;
		$base  = URI::file->new_abs($fn)->as_string;
		open $input, $fn;
	}

	if (ref $input eq 'GLOB')
	{
		local $/;
		local $_ = <$input>;
		$input->close;
		$input = $_;
	}
	
	if ($Has->{'RDF::RDFa::Parser'}
	and (($type||'') =~ m'atom'i or ((!defined $type) and $input =~ m'http://www.w3.org/2005/Atom')))
	{
		my $opts = RDF::RDFa::Parser::OPTS_ATOM();
		$opts->{'atom_parser'} = 1;
		my $p = RDF::RDFa::Parser->new($input, $base, $opts, $model->_store);
		$p->consume;
		return $model;
	}
	elsif ($Has->{'XML::Atom::OWL'}
	and (($type||'') =~ m'atom'i or ((!defined $type) and $input =~ m'http://www.w3.org/2005/Atom')))
	{
		my $p = XML::Atom::OWL->new($input, $base, undef, $model->_store);
		$p->consume;
		return $model;
	}
	elsif ($Has->{'RDF::RDFa::Parser'}
	and ($type||'') =~ m'svg'i)
	{
		my $opts = RDF::RDFa::Parser::OPTS_SVG();
		my $p = RDF::RDFa::Parser->new($input, $base, $opts, $model->_store);
		$p->consume;
		return $model;
	}
	elsif ($Has->{'XRD::Parser'}
	and (($type||'') =~ m'xrd'i or ((!defined $type) and $input =~ m'http://docs.oasis-open.org/ns/xri/xrd-1.0')))
	{
		my $p = XRD::Parser->new($input, $base, undef, $model->_store);
		$p->consume;
		return $model;
	}

	my $parser;

	if (defined $type)
	{
		if ($type =~ /rdf.?xml/i)
		{
			$parser = RDF::Trine::Parser->new('RDFXML');
		}
		elsif ($type =~ /json/i)
		{
			$parser = RDF::Trine::Parser->new('RDFJSON');
		}
		elsif ($type =~ /turtle/i)
		{
			$parser = RDF::Trine::Parser->new('Turtle');
		}
		elsif ($type =~ /ntriple/i)
		{
			$parser = RDF::Trine::Parser->new('NTriples');
		}
		elsif ($type =~ /nquad/i)
		{
			$parser = RDF::Trine::Parser->new('NQuads');
		}
		elsif ($type =~ /(xhtml|rdfa)/i)
		{
			$parser = RDF::Trine::Parser->new('RDFa');
		}
		else
		{
			eval { $parser = RDF::Trine::Parser->new($type); }
		}
	}
	
	unless ($parser)
	{
		if ($input =~ /^\s*\{/s)
		{
			$parser = RDF::Trine::Parser->new('RDFJSON');
		}
		elsif ($input =~ /<rdf:RDF/)
		{
			$parser = RDF::Trine::Parser->new('RDFXML');
		}
		elsif ($input =~ /<html/)
		{
			$parser = RDF::Trine::Parser->new('RDFa');
		}
		elsif ($input =~ /<http/)
		{
			$parser = RDF::Trine::Parser->new('Turtle');
		}
		elsif ($input =~ /\@prefix/)
		{
			$parser = RDF::Trine::Parser->new('Turtle');
		}
		else
		{
			$parser = RDF::Trine::Parser->new('RDFXML');
		}
	}

	if (defined $context)
	{
		$parser->parse_into_model($base, $input, $model, context=>$context);
	}
	else
	{
		$parser->parse_into_model($base, $input, $model);
	}

	return $model;
}

=item C<< rdf_string($model, $format) >>

Serialises an L<RDF::Trine::Model> to a string.

$model is the model to serialise. If $model is not an RDF::Trine::Model 
object, then it's automatically passed through rdf_parse first.

$format is the format to use. One of 'RDFXML' (the default), 'RDFJSON',
'Turtle', 'Canonical NTriples' or 'NTriples'. If $format is not one of the above, 
then the function will try to guess what you meant.

Preferred namespace names can be provided as a named argument:

 print rdf_string($model, 'turtle',
    namespaces => { foo=>'http://example.com/vocabs/foo#' });

=cut

sub rdf_string
{
	my $model = shift;
	my $fmt   = shift || 'RDFXML';
	my %args  = @_;
	my $s;
	
	$args{'namespaces'} = {
		dc   => 'http://purl.org/dc/terms/',
		dc11 => 'http://purl.org/dc/elements/1.1/',
		doap => 'http://usefulinc.com/ns/doap#',
		foaf => 'http://xmlns.com/foaf/0.1/',
		geo  => 'http://www.w3.org/2003/01/geo/wgs84_pos#',
		owl  => 'http://www.w3.org/2002/07/owl#',
		rdf  => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
		rdfs => 'http://www.w3.org/2000/01/rdf-schema#',
		sioc => 'http://rdfs.org/sioc/ns#',
		skos => 'http://www.w3.org/2004/02/skos/core#',
		v    =>	'http://www.w3.org/2006/vcard/ns#',
		xsd  => 'http://www.w3.org/2001/XMLSchema#',
		}
		unless defined $args{'namespaces'};

	unless (UNIVERSAL::isa($model, 'RDF::Trine::Model'))
	{
		$model = rdf_parse($model);
	}

	if ($fmt =~ /json/i)
	{
		$s = RDF::Trine::Serializer::RDFJSON->new;
	}
	elsif ($fmt =~ /xml/i)
	{
		$s = RDF::Trine::Serializer::RDFXML->new;
	}
	elsif ($fmt =~ /canon/i)
	{
		$s = RDF::Trine::Serializer::NTriples::Canonical->new;
	}
	elsif ($fmt =~ /turtle/i || $fmt =~ /n(otation)\s*3/i)
	{
		$s = RDF::Trine::Serializer::Turtle->new(namespaces=>$args{'namespaces'});
	}
	elsif ($fmt =~ /n\-?t/i)
	{
		$s = RDF::Trine::Serializer::NTriples->new;
	}
	else
	{
		$s = RDF::Trine::Serializer::RDFXML->new(namespaces=>$args{'namespaces'});
	}

	return $s->serialize_model_to_string($model);
}

=item C<< rdf_query($sparql, $endpoint) >>

$sparql is a SPARQL query to be run at $endpoint.

$endpoint may be either an endpoint URI (string or L<URI> object)
or a model supported by RDF::Query (e.g. an L<RDF::Trine::Model>.)

Query languages other than SPARQL may be used (see <RDF::Query> for
a list of supported languages). e.g.

  rdf_query("SELECT ?s, ?p, ?o WHERE (?s, ?p, ?o)"
            $model,
            query_lang=>'rdql');

The query_base option can be used to resolve relative URIs in the query.

If the SPARQL query returns a boolean (i.e. an ASK query), then
this function returns a boolean. If the query returns a graph (i.e.
CONSTRUCT or DESCRIBE), then this function returns an RDF::Trine::Model 
corresponding to the graph. Otherwise (i.e. SELECT) it returns an
L<RDF::Trine::Iterator> object.

For queries which return a graph, an optional $model parameter can be 
passed containing an existing RDF::Trine::Model to add statements to:

  rdf_query("CONSTRUCT {?s ?p ?o} WHERE {?s ?p ?o}",
            'http://example.com/sparql',
            model => $model);

=cut

sub rdf_query
{
	my $sparql   = shift;
	my $endpoint = shift;
	my %args     = @_;

	my $r;
	if (UNIVERSAL::isa($endpoint, 'URI') or !ref $endpoint)
	{
		# If $sparql is not usable as-is
		if (defined $args{'query_base'}
		or (defined $args{'query_lang'} && $args{'query_lang'} !~ /^sparql$/i))
		{
			# Then use RDF::Query to rewrite it.
			my $q = RDF::Query->new($sparql, $args{'query_base'}, undef, $args{'query_lang'});
			$sparql = $q->as_sparql;
		}
		
		my $q = RDF::Query::Client->new($sparql);
		$r = $q->execute("$endpoint");
	}
	else
	{
		my $q = RDF::Query->new($sparql, $args{'query_base'}, undef, $args{'query_lang'});
		$r = $q->execute($endpoint);
	}

	if ($r->is_boolean)
	{
		return $r->get_boolean;
	}
	elsif ($r->is_graph)
	{
		return rdf_parse($r, %args);
	}
	else
	{
		return $r;
	}
}

=item C<< rdf_node($value, %args) >>

Creates an RDF::Trine::Node object.

Will attempt to automatically determine whether $value is a blank node,
resource or literal, but an optional named argument 'type' can be used
to explicitly indicate this.

For literals, named arguments 'datatype' and 'lang' are allowed. If
'datatype' is not a URI, then it's assumed to be an XSD datatype.

 $node = rdf_node("Hello", type=>'literal', lang=>'en');

For resources, the named argument 'base' is allowed.

This function is not exported by default, but can be exported using
the tag ':nodes' or ':all'.

 use RDF::TrineShortcuts qw(:default :nodes);

=cut

sub rdf_node
{
	my $value = shift;
	my %args  = @_;
	
	return $value
		if UNIVERSAL::isa($value, 'RDF::Trine::Node');
	
	if (defined ($args{'datatype'} || $args{'lang'} || $args{'language'}))
	{
		$args{'type'} ||= 'literal';
	}
	elsif ($value =~ /^_:(.*)$/)
	{
		$args{'type'} ||= 'blank';
		$value = $1 if $args{'type'} =~ /(blank|bnode)/i;
	}
	elsif ($value =~ /^[a-z0-9\+\-]+:\S*$/i)
	{
		$args{'type'} ||= 'resource';
	}
	elsif (UNIVERSAL::isa($value, 'DateTime'))
	{
		$value              = "$value";
		$args{'type'}     ||= 'literal';
		$args{'datatype'} ||= 'dateTime' unless $args{'lang'};
	}
	elsif (UNIVERSAL::isa($value, 'URI'))
	{
		$value              = "$value";
		$args{'type'}     ||= 'resource';
		$args{'datatype'} ||= 'anyURI' unless $args{'lang'};
	}
	else
	{
		$args{'type'} ||= 'literal';
	}
	
	if ($args{'type'} =~ /(uri|url|resource)/i)
	{
		if ($args{'base'})
		{
			$value = URI->new_abs("$value", $args{'base'});
			$value = "$value";
		}
		
		return RDF::Trine::Node::Resource->new($value);
	}
	
	elsif ($args{'type'} =~ /(bnode|blank)/i)
	{
		return RDF::Trine::Node::Blank->new($value);
	}
	
	else
	{
		if (defined $args{'datatype'}
		&& length $args{'datatype'}
		&& $args{'datatype'} !~ /^[a-z0-9\+\-]+:\S*$/i)
		{
			$args{'datatype'} = sprintf('http://www.w3.org/2001/XMLSchema#%s',
				$args{'datatype'});
		}
		
		return RDF::Trine::Node::Literal->new($value, $args{'lang'}||$args{'language'}, $args{'datatype'});
	}
}

=item C<< rdf_literal($value, %args) >>,
C<< rdf_blank($value, %args) >>, 
C<< rdf_resource($value, %args) >>

Shortcuts for rdf_node($value, type=>'literal', %args) and so on.

These functions are not exported by default, but can be exported using
the tag ':nodes' or ':all'.

 use RDF::Trine qw(:all);

=cut

sub rdf_literal
{
	my $value = shift;
	return rdf_node($value, type=>'literal', @_);
}

sub rdf_blank
{
	my $value = shift;
	return rdf_node($value, type=>'blank', @_);
}

sub rdf_resource
{
	my $value = shift;
	return rdf_node($value, type=>'resource', @_);
}

=item C<< rdf_statement($s, $p, $o, [$g]) >>, 
C<< rdf_statement($ntriple, [$g]) >>

Returns an RDF::Trine::Statement. Parameters $s, $p, $o and $g
can each be either a plain string that could be passed to rdf_node,
or an arrayref of rdf_node parameters, or an RDF::Trine::Node.

$ntriple is a single N-Triples statement.

This function is not exported by default, but can be exported using
the tag ':all'.

 use RDF::Trine qw(:all);

=cut

sub rdf_statement
{
	my ($s, $p, $o, $g) = @_;
	
	if (!defined ($o||$g))
	{
		(my $ntriple, $g, $p) = ($s, $p, undef);
		$ntriple .= ' .' unless $ntriple =~ /\.[\s\r\n]*$/;
		my $model = rdf_parse($ntriple, type=>'ntriples');
		my $iter  = $model->as_stream;
		if (my $st = $iter->next)
		{
			return $st;
		}
		else
		{
			die "Could not parse N-Triples statement";
		}
	}

	if (ref $s eq 'ARRAY')
	{
		$s = rdf_node(@$s);
	}
	else
	{
		$s = rdf_node($s);
	}

	if (ref $p eq 'ARRAY')
	{
		$p = rdf_resource(@$p);
	}
	else
	{
		$p = rdf_resource($p);
	}

	if (ref $o eq 'ARRAY')
	{
		$o = rdf_node(@$o);
	}
	else
	{
		$o = rdf_node($o);
	}

	if (ref $g eq 'ARRAY')
	{
		$g = rdf_node(@$g);
	}
	elsif (defined $g)
	{
		$g = rdf_node($g);
	}

	if (defined $g)
	{
		return RDF::Trine::Statement->new($s, $p, $o, $g);
	}
	else
	{
		return RDF::Trine::Statement->new($s, $p, $o);
	}
}

1;

__END__

=back

=head1 BUGS

Please report any bugs to L<http://rt.cpan.org/>.

=head1 SEE ALSO

L<RDF::Trine>, L<RDF::Query>, L<RDF::Query::Client>.

L<http://www.perlrdf.org/>.

This module is distributed with three command-line RDF tools.
L<trapper> is an RDF fetcher/parser/serialiser;
L<toquet> is a SPARQL query tool;
L<trist> is an RDF statistics tool.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT

Copyright 2010 Toby Inkster

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

