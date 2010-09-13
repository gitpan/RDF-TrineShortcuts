package RDF::TrineShortcuts;

=head1 NAME

RDF::TrineShortcuts - totally unauthorised module for cheats and charlatans

=head1 VERSION

0.101

=head1 SYNOPSIS

  use RDF::TrineShortcuts;
  
  my $model = rdf_parse('http://example.com/data.rdf');
  my $query = 'ASK { ?person a <http://xmlns.com/foaf/0.1/Person> . }';
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
use RDF::Trine '0.123';
use RDF::Trine::Serializer;
use RDF::Query '2.900';
use RDF::Query::Client;
use Scalar::Util qw(blessed);
use URI;
use URI::file;

our @ISA      = qw(Exporter);
our %EXPORT_TAGS = (
	default => [qw(rdf_parse rdf_string rdf_query)],
	nodes   => [qw(rdf_node rdf_literal rdf_blank rdf_resource)],
	flatten => [qw(flatten_iterator flatten_node)],
	all     => [qw(rdf_parse rdf_string rdf_query rdf_node rdf_literal rdf_blank rdf_resource rdf_statement flatten_iterator flatten_node)],
	);
our @EXPORT    = @{ $EXPORT_TAGS{'default'} };
our @EXPORT_OK = @{ $EXPORT_TAGS{'all'} };
our %PRAGMATA  = (
	'methods' => \&install_methods,
	);
our $VERSION   = '0.101';
my $Has;

our $Namespaces = {
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
	};

BEGIN
{
	$Has = {};
	foreach my $package (qw(XML::Atom::OWL RDF::TriN3
		HTTP::Link::Parser XRD::Parser RDF::RDFa::Parser
		RDF::RDFa::Generator))
	{
		$@ = undef;
		my $r = eval "use $package; return \$${package}::VERSION;";
		$Has->{$package} = 1 unless $@;
		if ($r && $Has->{$package})
		{
			$Has->{$package} = $r;
		}
	}
}

# Totally stolen from Pragmatic on CPAN
# It's OK - licence allows.
sub import ($)
{
	my $argc    = scalar(@_);
	my $package = shift;

	my $warn = sub (;$) {
		require Carp;
		local $Carp::CarpLevel = 2; # relocate to calling package
		Carp::carp (@_);
	};

	my $die = sub (;$) {
		require Carp;
		local $Carp::CarpLevel = 2; # relocate to calling package
		Carp::croak (@_);
	};

	my @imports = grep /^[^-]/, @_;
	my @pragmata = map { substr($_, 1); } grep /^-/, @_;
	
	if ($argc==1 && !@imports && !@pragmata)
	{
		push @imports, ':default';
	}

	# Export first, for side-effects (e.g., importing globals, then
	# setting them with pragmata):
	$package->export_to_level (1, $package, @imports)
		if @imports;

	for (@pragmata)
	{
		no strict qw (refs);

		my ($pragma, $args) = split /=/, $_;
		my (@args) = split /,/, $args || '';

		exists ${"$package\::PRAGMATA"}{$pragma}
		or &$die ("No such pragma '$pragma'");

		if (ref ${"$package\::PRAGMATA"}{$pragma} eq 'CODE')
		{
			&{${"$package\::PRAGMATA"}{$pragma}} ($package, @args)
				or &$warn ("Pragma '$pragma' failed");
			# Let inheritance work for barewords:
		}
		elsif (my $ref = $package->can(${"$package\::PRAGMATA"}{$pragma}))
		{
			&$ref ($package, @args)
				or &$warn ("Pragma '$pragma' failed");
		}
		else
		{
			&$die ("Invalid pragma '$pragma'");
		}
	}
}

=head1 DESCRIPTION

This module exports three functions which simplify frequently performed 
tasks using L<RDF::Trine> and L<RDF::Query>. (A number of other
functions are also available but not exported by default.)

=over 4

=item * C<rdf_parse($data)>

=item * C<rdf_string($model, $format)>

=item * C<rdf_query($sparql, $endpoint_or_model)>

=back

In addition, because it calls "use RDF::Trine", "use RDF::Query", and
"use RDF::Query::Client", your code doesn't need to.

=head2 Main Functions

=over 4

=item C<< rdf_parse($data) >>

$data can be some serialised RDF (in RDF/XML, Turtle, RDF/JSON, or any 
other format that L<RDF::Trine::Parser> supports); or a URI (string or 
L<URI> object); or an L<HTTP::Message> object; or a hashref (as per 
RDF::Trine::Model's add_hashref method); or a file name or an open file 
handle; or an L<RDF::Trine::Iterator::Graph>. Essentially it could be 
anything you could reasonably expect to grab RDF from. It can be undef.

If $input is a blessed object that rdf_parse is unable to natively deal with,
it will attempt to call C<< $input->TO_RDF >> and deal with the result
instead. (This is similar in spirit to the L<JSON> module's convert_blessed
functionality.)

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
	my $context = rdf_node($args{'context'}, passthrough_undef=>1);
	my $type    = $args{'type'};
	my $base    = $args{'base'};

	return $model unless defined $input;

	eval
	{
		if ($input =~ /^([A-Za-z0-9_]+)(\;[^\r\n]*)?$/
			  && "RDF::Trine::Store::$1"->isa("RDF::Trine::Store"))
		{
			$input = RDF::Trine::Store->new_with_string($input);
		}
	};
	
	if (blessed($input) && $input->can('TO_RDF'))
	{
		return rdf_parse($input->TO_RDF, %args);
	}

	if (blessed($input) && $input->isa('RDF::Trine::Store'))
	{
		$input = RDF::Trine::Model->new($input);
	}

	if (blessed($input) && $input->isa('RDF::Trine::Model'))
	{
		if ($context)
		{
			$input = $input->get_statements(undef,undef,undef);
		}
		else
		{
			$input = $input->get_statements(undef,undef,undef,undef);
		}
	}

	if (blessed($input) && $input->isa('RDF::Trine::Iterator'))
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

	if (blessed($input) && $input->isa('URI')
	or  $input =~ m'^(https?|ftp|file):\S+$')
	{
		my $accept = 'application/rdf+xml, text/turtle, application/x-trig, text/x-nquads, application/json;q=0.1, application/xhtml+xml;q=0.1';
		$accept .= ', application/atom+xml;q=0.2' if $Has->{'XML::Atom::OWL'};
		$accept .= ', application/xrd+xml;q=0.2'  if $Has->{'XRD::Parser'};
		
		my $ua = LWP::UserAgent->new;
		$ua->agent(sprintf('%s/%s ', __PACKAGE__, $VERSION));
		$ua->default_header("Accept" => $accept);

		$input = $ua->get("$input");
	}

	if (blessed($input) && $input->isa('HTTP::Message'))
	{		
		if ($Has->{'HTTP::Link::Parser'} && !$args{'no_http_links'})
		{
			HTTP::Link::Parser::parse_links_into_model($input, $model);
		}
		
		$type ||= $input->content_type;
		$base ||= $input->base;
		$input  = $input->decoded_content;
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
	
	if ($Has->{'RDF::RDFa::Parser'} gt '1.09'
	and $type =~ m#/#)
	{
		my $host = RDF::RDFa::Parser::Config->host_from_media_type($type);
		if (defined $host)
		{
			my $config = RDF::RDFa::Parser::Config->new($host);
			my $parser = RDF::RDFa::Parser->new($input, $base, $config, $model->_store);
			$parser->consume;
			return $model;
		}
	}
	
	if ($Has->{'RDF::RDFa::Parser'} gt '1.09'
	and (($type||'') =~ m'atom'i or ((!defined $type) and $input =~ m'http://www.w3.org/2005/Atom')))
	{
		my $opts = RDF::RDFa::Parser::Config->new('atom', '1.1', atom_parser=>1);
		my $p = RDF::RDFa::Parser->new($input, $base, $opts, $model->_store);
		$p->consume;
		return $model;
	}
	elsif ($Has->{'RDF::RDFa::Parser'}
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
	elsif ($Has->{'RDF::RDFa::Parser'}  gt '1.09'
	and ($type||'') =~ m'svg'i)
	{
		my $opts = RDF::RDFa::Parser::Config->new('svg', '1.1', atom_parser=>1);
		my $p = RDF::RDFa::Parser->new($input, $base, $opts, $model->_store);
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
	elsif ($Has->{'RDF::RDFa::Parser'}  gt '1.09'
	and ($type||'') =~ m'opendoc'i)
	{
		my $opts = RDF::RDFa::Parser::Config->new('opendocument-zip', '1.1');
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
		elsif ($type =~ /n3/i)
		{
			$parser = $Has->{'RDF::TriN3'} ?
				RDF::Trine::Parser::Notation3->new() :
				RDF::Trine::Parser->new('Turtle');
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
		elsif ($type =~ /trig/i)
		{
			$parser = RDF::Trine::Parser->new('TriG');
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
			$parser = $Has->{'RDF::TriN3'} ?
				RDF::Trine::Parser::Notation3->new() :
				RDF::Trine::Parser->new('Turtle');
		}
		elsif ($input =~ /\@prefix/)
		{
			$parser = $Has->{'RDF::TriN3'} ?
				RDF::Trine::Parser::Notation3->new() :
				RDF::Trine::Parser->new('Turtle');
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

You can find the relevant Internet media type like this:

 my $type;
 my $string = rdf_string($model, 'rdfxml', media_type=>\$type);
 print $cgi->header($type), $string and exit;

=cut

sub rdf_string
{
	my $model = shift;
	my $fmt   = shift || 'RDFXML';
	my %args  = @_;
	my $s;
	my $media;
	
	$args{'namespaces'} ||= $Namespaces;

	unless (blessed($model) && $model->isa('RDF::Trine::Model'))
	{
		$model = rdf_parse($model);
	}

	if ($fmt =~ /json/i)
	{
		$s = RDF::Trine::Serializer::RDFJSON->new;
		$media = 'application/json';
	}
	elsif ($fmt =~ /(rdfa|html)/i && $Has->{'RDF::RDFa::Generator'})
	{
		$args{'style'} ||= 'HTML::Hidden';
		$s = RDF::RDFa::Generator->new(%args);
		$media = 'application/xhtml+xml';
	}
	elsif ($fmt =~ /xml/i)
	{
		$s = RDF::Trine::Serializer::RDFXML->new(namespaces=>$args{'namespaces'});
		$media = 'application/rdf+xml';
	}
	elsif ($fmt =~ /canon/i)
	{
		$s = RDF::Trine::Serializer::NTriples::Canonical->new;
		$media = 'text/plain';
	}
	elsif ($fmt =~ /n(otation)?\s*3/i)
	{
		$s = RDF::Trine::Serializer::Notation3->new(namespaces=>$args{'namespaces'});
		$media = 'text/n3';
	}
	elsif ($fmt =~ /turtle/i)
	{
		$s = RDF::Trine::Serializer::Turtle->new(namespaces=>$args{'namespaces'});
		$media = 'text/turtle';
	}
	elsif ($fmt =~ /n\-?t/i)
	{
		$s = RDF::Trine::Serializer::NTriples->new;
		$media = 'text/plain';
	}
	elsif ($fmt =~ /n\-?q/i)
	{
		$s = RDF::Trine::Serializer::NQuads->new;
		$media = 'text/x-nquads';
	}
	else
	{
		$s = RDF::Trine::Serializer::RDFXML->new(namespaces=>$args{'namespaces'});
		$media = 'application/rdf+xml';
	}

	if (ref $args{'media_type'})
	{
		${ $args{'media_type'} } = $media;
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

Options query_base, query_update and query_load_data correspond to
the base, update and load_data options passed to RDF::Query's
constructor.

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

This function can expand a small set of commonly used prefixes. For
example:

 $result = rdf_query('SELECT ?id ?name {?id foaf:name ?name}',
                     $model);

The hashref $RDF::TrineShortcuts::Namespaces is consulted for expansions.

=cut

sub rdf_query
{
	my $sparql   = shift;
	my $endpoint = shift;
	my %args     = @_;
	
	if (!defined $args{query_update})
	{
		$args{query_update} = 0;
	}

	if (!defined $args{query_load_data})
	{
		$args{query_load_data} = 0;
	}

	my $r;
	if (blessed($endpoint) && $endpoint->isa('URI') or !ref $endpoint)
	{
		# If $sparql is not usable as-is
		if (defined $args{'query_base'}
		or (defined $args{'query_lang'} && $args{'query_lang'} !~ /^sparql(11)?$/i))
		{
			# Then use RDF::Query to rewrite it.
			my $q = RDF::Query->new($sparql, {
				base      => $args{'query_base'},
				lang      => $args{'query_lang'},
				update    => $args{'query_update'},
				load_data => $args{'query_load_data'},
				});
			$sparql = $q->as_sparql;
		}
		
		$sparql = sparql_garnish_namespaces($sparql)
			unless $args{'trust_prefixes'};
		
		my $q = RDF::Query::Client->new($sparql);
		$r = $q->execute("$endpoint");
	}
	else
	{
		$sparql = sparql_garnish_namespaces($sparql)
			unless $args{'trust_prefixes'};
		
		my $q = RDF::Query->new($sparql, {
			base      => $args{'query_base'},
			lang      => $args{'query_lang'},
			update    => $args{'query_update'},
			load_data => $args{'query_load_data'},
			});
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

sub sparql_garnish_namespaces
{
	my $q = shift;
	while (my($p,$u) = each %$Namespaces)
	{
		next unless $q =~ /$p:/;
		next if $q =~ /\bprefix\s+$p\s*:/i;
		$q = sprintf("PREFIX %s: <%s>\n", $p, $u) . $q;
	}
	return $q;
}

=back

=head2 Additional Functions

These are not exported by default, so need to be imported explicitly, e.g.

 use RDF::TrineShortcuts qw(:default rdf_node rdf_statement);

=over 4

=item C<< rdf_node($value, %args) >>

Creates an RDF::Trine::Node object.

Will attempt to automatically determine whether $value is a blank node,
resource or literal, but an optional named argument 'type' can be used
to explicitly indicate this.

For literals, named arguments 'datatype' and 'lang' are allowed. If
'datatype' is not a URI, then it's assumed to be an XSD datatype.

 $node = rdf_node("Hello", type=>'literal', lang=>'en');

For resources, the named argument 'base' is allowed.

If $value is undef, then it would normally be treated like a zero-length
string. By setting the argument 'passthrough_undef' to 1, you can allow
it to pass thorugh and return undef.

This function can expand a small set of commonly used prefixes. For
example:

 $node = rdf_node('foaf:primaryTopic');

The hashref $RDF::TrineShortcuts::Namespaces is consulted for expansions.

This function is not exported by default, but can be exported using
the tag ':nodes' or ':all'.

 use RDF::TrineShortcuts qw(:default :nodes);

=cut

sub rdf_node
{
	my $value = shift;
	my %args  = @_;
	
	return $value
		if blessed($value) && $value->isa('RDF::Trine::Node');
	
	return undef
		if !defined($value) && $args{'passthrough_undef'};
	$value = '' unless defined $value;		
	
	if (defined ($args{'datatype'} || $args{'lang'} || $args{'language'}))
	{
		$args{'type'} ||= 'literal';
	}
	elsif ($value =~ /^_:(.*)$/)
	{
		$args{'type'} ||= 'blank';
		$value = $1 if $args{'type'} =~ /(blank|bnode)/i;
	}
	elsif ($value =~ /^([a-z0-9\+\-]+):([a-z0-9\_\+\-]*)$/i && defined $Namespaces->{$1})
	{
		$args{'type'} ||= 'resource';
		$value = $Namespaces->{$1} . $2;
	}
	elsif ($value =~ /^[a-z0-9\+\-]+:\S*$/i)
	{
		$args{'type'} ||= 'resource';
	}
	elsif (blessed($value) && $value->isa('DateTime'))
	{
		$value              = "$value";
		$args{'type'}     ||= 'literal';
		$args{'datatype'} ||= 'dateTime' unless $args{'lang'};
	}
	elsif (blessed($value) && $value->isa('URI'))
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

Shortcuts for rdf_node($value, type=>'literal', %args) and so on. The
rdf_resource function will create a blank node resource if $value begins
'_:'.

These functions are not exported by default, but can be exported using
the tag ':nodes' or ':all'.

 use RDF::TrineShortcuts qw(:all);

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
	return rdf_node($value, type=>'blank', @_) if $value =~ /^_:/;
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

 use RDF::TrineShortcuts qw(:all);

=cut

sub rdf_statement
{
	my ($s, $p, $o, $g) = @_;
	
	if (!defined $o && !defined $g)
	{
		(my $ntriple, $g, $p) = ($s, $p, undef);
		$ntriple .= ' .' unless $ntriple =~ /\.[\s\r\n]*(#[^\r\n]*)?$/;
		my $model = rdf_parse($ntriple, type=>'ntriples', context=>$g);
		my $iter  = $model->get_statements(undef,undef,undef,undef);
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

=item C<< flatten_node($node) >>

Converts a node back to a string.

By default, blank nodes and variables are stringified to their N-Triples
and SPARQL representations; URIs are stringified without angled bracket
delimiters; and literals to their literal values.

Various options are available: 'resource_as', 'blank_as', 'variable_as'
and 'literal_as' can each be set to 'ntriples', 'value' or 'default'.

 print flatten_node($my_resource, resource_as=>'ntriples');

This function is not exported by default, but can be exported using
the tag ':flatten' or ':all'.

 use RDF::TrineShortcuts qw(:default :flatten);

=cut

sub flatten_node
{
	my ($node, %args) = @_;
	
	return undef unless defined $node;
	
	$args{'resource_as'}  ||= 'value';
	$args{'literal_as'}   ||= 'value';
	$args{'blank_as'}     ||= 'ntriples';
	$args{'varible_as'}   ||= 'ntriples';
	
	if (blessed($node) && $node->isa('RDF::Trine::Node'))
	{
		return $node if $args{'keep_nodes'};
		
		if ($node->isa('RDF::Trine::Node::Literal') && $args{'literal_as'} =~ m'ntriple')
		{
			return $node->as_ntriples;
		}
		elsif($node->isa('RDF::Trine::Node::Literal'))
		{
			return $node->literal_value;
		}
		elsif ($node->isa('RDF::Trine::Node::Resource') && $args{'resource_as'} =~ m'ntriple')
		{
			return $node->as_ntriples;
		}
		elsif($node->isa('RDF::Trine::Node::Resource'))
		{
			return $node->uri;
		}
		elsif ($node->isa('RDF::Trine::Node::Blank') && $args{'blank_as'} =~ m'value')
		{
			return $node->blank_identifier;
		}
		elsif($node->isa('RDF::Trine::Node::Blank'))
		{
			return $node->as_ntriples;
		}
		elsif ($node->isa('RDF::Trine::Node::Variable') && $args{'variable_as'} =~ m'value')
		{
			return $node->name;
		}
		elsif($node->isa('RDF::Trine::Node::Variable'))
		{
			return $node->as_string;
		}
	}
	else
	{
		return flatten_node(rdf_node($node), %args)
	}
	
	return undef;
}

=item C<< flatten_iterator($iter) >>

Converts an iterator to a Perl list. In list context returns a list; in
scalar context returns an arrayref instead.

Each item in the list is, in the case of a bindings iterator, a hashref; or,
in the case of a triple/quad iterator, an arrayref [s, p, o, g]. For boolean
iterators, $iter->get_boolean is returned. The nodes which are values in the
hashref/arrayref are flattened with flatten_node, unless flatten_iterator is
called with 'keep_nodes'=>1.

  my @results = flatten_iterator($iter, keep_nodes=>1);
  
You can pass additional options for flatten_node too:

  my @results = flatten_iterator($iter, resource_as=>'ntriples');

This function is not exported by default, but can be exported using
the tag ':flatten' or ':all'.

 use RDF::TrineShortcuts qw(:default :flatten);

=cut

sub flatten_iterator
{
	my ($iter, %args) = @_;
	my @rv;
	
	return undef unless blessed($iter) && $iter->isa('RDF::Trine::Iterator');
	
	if ($iter->is_bindings)
	{
		while (my $r = $iter->next)
		{
			my $x = {};
			while (my ($key, $node) = each %$r)
			{
				$x->{$key} = flatten_node($node, %args);
			}
			push @rv, $x;
		}
	}
	elsif ($iter->is_graph)
	{
		while (my $st = $iter->next)
		{
			my @x = map { flatten_node($_, %args) } $st->nodes;
			push @rv, \@x;
		}
	}
	elsif ($iter->is_boolean)
	{
		return $iter->get_boolean;
	}
	
	return wantarray ? @rv : \@rv;
}

=back

=head2 Object-Oriented Interface

RDF::TrineShortcuts has an alternative, object-oriented interface, not enabled
by default.

 use RDF::TrineShortcuts -methods;
 
 my $model = RDF::Trine::Model->temporary_model;
 
 # Alias for rdf_parse($some_turtle, model=>$model) 
 $model->parse($some_turtle);
 
 # Alias for rdf_string($model, 'rdfxml');
 my $rdfxml = $model->parse('rdfxml');
 print $rdfxml;
 
 my $query = 'SELECT ?name WHERE { ?id foaf:name ?name . } ';
 
 # Alias for rdf_query($query, $model);
 my $result = $model->sparql($query);
 
 # Alias for flatten_iterator();
 my @result = $result->flatten;

And so on. The following methods are set up:

=over 4

=item * RDF::Trine::Model: C<parse>, C<string>, C<sparql>.

=item * RDF::Trine::Node: C<flatten>.

=item * RDF::Trine::Iterator: C<flatten>.

=item * URI::http: C<sparql>.

=item * URI: C<resource>.

=back

Future versions of the RDF::Trine and URI packages may break this. It's a pretty
dodgy feature.

You can load the normal RDF::TrineShortcuts function-based interface in addition
to the object-oriented interface like this:

 use RDF::TrineShortcuts qw(:default -methods);

Or everything:

 use RDF::TrineShortcuts qw(:all -methods);

=cut

sub install_methods
{
	*RDF::Trine::Node::flatten = sub {
		my ($node, @args) = @_;
		return RDF::TrineShortcuts::flatten_node($node, @args);
	};
	*RDF::Trine::Iterator::flatten = sub {
		my ($iter, @args) = @_;
		return RDF::TrineShortcuts::flatten_iterator($iter, @args);
	};
	*RDF::Trine::Model::parse = sub {
		my ($model, $data, %args) = @_;
		$args{'model'} = $model;
		return RDF::TrineShortcuts::rdf_parse($data, %args);
	};
	*RDF::Trine::Model::string = sub {
		my ($model, $format, %args) = @_;
		return RDF::TrineShortcuts::rdf_string($model, $format, %args);
	};
	*RDF::Trine::Model::sparql = sub {
		my ($model, $query, %args) = @_;
		return RDF::TrineShortcuts::rdf_query($query, $model, %args);
	};
	*URI::http::sparql = sub {
		my ($endpoint, $query, %args) = @_;
		return RDF::TrineShortcuts::rdf_query($query, $endpoint, %args);
	};
	*URI::resource = sub {
		my ($uri, %args) = @_;
		return RDF::TrineShortcuts::rdf_resource($uri, %args);
	};
}

1;

__END__

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

