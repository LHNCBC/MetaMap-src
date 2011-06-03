/****************************************************************************
*
*                          PUBLIC DOMAIN NOTICE                         
*         Lister Hill National Center for Biomedical Communications
*                      National Library of Medicine
*                      National Institues of Health
*           United States Department of Health and Human Services
*                                                                         
*  This software is a United States Government Work under the terms of the
*  United States Copyright Act. It was written as part of the authors'
*  official duties as United States Government employees and contractors
*  and thus cannot be copyrighted. This software is freely available
*  to the public for use. The National Library of Medicine and the
*  United States Government have not placed any restriction on its
*  use or reproduction.
*                                                                        
*  Although all reasonable efforts have been taken to ensure the accuracy 
*  and reliability of the software and data, the National Library of Medicine
*  and the United States Government do not and cannot warrant the performance
*  or results that may be obtained by using this software or data.
*  The National Library of Medicine and the U.S. Government disclaim all
*  warranties, expressed or implied, including warranties of performance,
*  merchantability or fitness for any particular purpose.
*                                                                         
*  For full details, please see the MetaMap Terms & Conditions, available at
*  http://metamap.nlm.nih.gov/MMTnCs.shtml.
*
***************************************************************************/

% File:	    metamap_variants.pl
% Module:   MetaMap
% Author:   Lan
% Purpose:  MetaMap variant generation


:- module(metamap_variants,[
	initialize_metamap_variants/1,
	compute_variant_generators/3,
	augment_GVCs_with_variants/1,
	gather_variants/4,
	write_all_variants/1
    ]).

:- use_module(lexicon(lex_access),[
	is_a_base_form/1,
	is_a_base_form_with_categories/2,
	is_a_form/1,
	get_variants_for_citation_form/2,
	get_variants_for_form/2,
	get_derivational_variants_for_form/3,
	get_categories_for_form/2,
	get_spellings_and_inflections_for_form/4,
	get_citation_forms_for_form/3,
	get_base_forms_for_form/3
    ]).


:- use_module(metamap(aao), [
	aao/1
   ]).

:- use_module(metamap(metamap_tokenization),[
	tokenize_text_mm_lc/2
    ]).

:- use_module(metamap(metamap_utilities),[
	positions_overlap/2,
	dump_variants_labelled/2
    ]).

:- use_module(metamap(vdx), [
	vdx/2
   ]).

:- use_module(skr(skr_utilities), [
	expand_split_word_list/2,
	split_word/3
   ]).

:- use_module(skr_db(db_access),[
	db_get_synonyms/2,
	db_get_synonyms/3,
	db_get_all_acros_abbrs/2,
	db_get_unique_acros_abbrs/2,
	db_get_variants/3
    ]).

:- use_module(skr_lib(nls_avl), [
	add_to_avl/4,
	add_to_avl_once/4
   ]).

:- use_module(skr_lib(nls_system),[
	control_option/1
    ]).

:- use_module(skr_lib(sicstus_utils),[
	lower/2
    ]).

:- use_module(library(avl),[
	empty_avl/1,
	avl_fetch/3
    ]).

:- use_module(skr_lib(nls_text),[
	concatenate_text/3
    ]).

:- use_module(skr_lib(nls_strings),[
	concatenate_items_to_atom/2
    ]).

:- use_module(lexicon(lexical),[
	lowercase_list/2
    ]).

:- use_module(library(codesio),[
	with_output_to_codes/2
    ]).

:- use_module(library(lists),[
	append/2,
	last/2,
	rev/2
    ]).

:- use_module(library(ordsets),[
	ord_subtract/3
    ]).

:- use_module(library(sets),[
	intersection/3,
	list_to_set/2
    ]).

:- dynamic generation_mode/1.


/* ************************************************************************
   ************************************************************************
   ************************************************************************
                       MetaMap Variant Generation Predicates
   ************************************************************************
   ************************************************************************
   ************************************************************************ */


/* initialize_metamap_variants(+Mode)

initialize_metamap_variants/1 sets generation mode to Mode.  Unless the mode
is explicitly set to static, MetaMap Variants generates variants dynamically,
i.e., using the variant generation algorithm rather than using db_access
to look up the result.  */

initialize_metamap_variants(Mode) :-
	% already initialized
	generation_mode(Mode),
	!.
initialize_metamap_variants(Mode) :-
	retractall(generation_mode(_)),
	conditionally_announce_generation_mode(Mode),
	assert(generation_mode(Mode)).

conditionally_announce_generation_mode(Mode) :-
	( \+ control_option(silent) ->
	  format('Variant generation mode: ~p.~n', [Mode])
	; true
	).

/* variant_score(?VariantType, ?Score)

variant_score/2 is a factual predicate defining the variant Score for each
VariantType.  */

variant_score(spelling,   0).
variant_score(inflection, 1).
variant_score(acro_abbr,  2).
variant_score(synonym,    2).
variant_score(derivation, 3).


/* compute_variant_generators(+Words, -VGenerators)
   compute_variant_generators_aux(+Words, -VGenerators)
   compute_variant_generators_1(+Word, +RevWords, -VGenerators)

compute_variant_generators/2
compute_variant_generators_aux/2
compute_variant_generators/3

xxx
Each VGenerator is an incomplete gvc (Generator/Variants/Candidates) term of
the form
    gvc(v(Word,Categories,VarLevel,History,_,_),_,_)
*/

compute_variant_generators(PhraseWords, DupPhraseWords, GVCs) :-
	( PhraseWords = DupPhraseWords ->
	  compute_variant_generators_1(PhraseWords, GVCs)
	; compute_variant_generators_1(PhraseWords, PhraseWordsGVCs),
	  compute_variant_generators_1(DupPhraseWords, DupPhraseWordsGVCs),
	  append(PhraseWordsGVCs, DupPhraseWordsGVCs, GVCs)
	).

compute_variant_generators_1(Words, GVCs) :-
	compute_variant_generators_aux(Words, GVCs0),
	% remove duplicates keeping first occurrence
	rev(GVCs0, GVCs1),
	% Vgenerators0 could have duplicates if a word
	% occurs in the phrase more than once!
	list_to_set(GVCs1, GVCs2),
	rev(GVCs2, GVCs),
	augment_generators_with_roots(GVCs).

compute_variant_generators_aux([], []).
compute_variant_generators_aux([First|Rest], GVCs) :-
	rev(Rest, RevRest),
	compute_variant_generators_1(RevRest, First, GVCsFirst),
	append(GVCsFirst, GVCsRest, GVCs),
	compute_variant_generators_aux(Rest,GVCsRest).

compute_variant_generators_1([], Word, GVCs) :-
	compute_variant_generators_for_word(Word, GVCs).

% compute_variant_generators_1([], Word, []) :-
% 	format('####################### ~w ###############~n', [Word]).
compute_variant_generators_1([H|T], Word, GVCs) :-
	RevRest = [H|T],
	rev(RevRest, Rest),
	concatenate_text([Word|Rest], ' ', MultiWord),
	is_a_form(MultiWord),  % multi-word items must be in lexicon
	!,
	compute_variant_generators_for_word(MultiWord, FirstGVCs),
	append(FirstGVCs, RestGVCs, GVCs),
	RevRest = [_|RevRestRest],
	compute_variant_generators_1(RevRestRest, Word, RestGVCs).

compute_variant_generators_1([_|RevRestRest],Word, GVCs) :-
	compute_variant_generators_1(RevRestRest,Word, GVCs).

compute_variant_generators_for_word(Word, VariantGenerators) :-
	get_categories_for_word(Word, LexicalCategories),
        create_generators(LexicalCategories, Word, VariantGenerators).

get_categories_for_word(Word, Categories) :-
	( is_a_form(Word),  % single words need not be in lexicon
	  get_categories_for_form(Word, Categories) ->
	  true
	; Categories = []
	).

create_generators([], Word, VariantGenerators) :-
        VariantGenerators = [gvc(v(Word,[],0,"",_,_),_,_)].
create_generators([H|T], Word, VariantGenerators) :-
        split_generator([H|T], Word, 0, [], _Roots, _NFR, VariantGenerators).
        
% VarLevel, History, Roots, and NFR all come in as anonymous variables,
% but they must be the same in each gvc/3 term.

split_generator([], _Word, _VarLevel, _History, _Roots, _NFR, []).
split_generator([First|Rest], Word, VarLevel, History, Roots, NFR,
                [gvc(v(Word,[First],VarLevel,History,Roots,NFR),_,_)|SplitRest]) :-
        split_generator(Rest, Word, VarLevel, History, Roots, NFR, SplitRest).


% VarLevel, History, Roots, and NFR they must be the same in each gvc/3 term,
% including the same free variable.

% split_generator([], _Word, _VarLevel, _History, _Roots, _NFR, []).
% split_generator([First|Rest], Word, VarLevel, History, Roots, NFR,
%                 [gvc(v(Word,[First],VarLevel,History,Roots,NFR),_,_)|SplitRest]) :-
% 	split_generator(Rest, Word, VarLevel, History, Roots, NFR, SplitRest).

/* augment_GVCs_with_variants(?GVCs)
   augment_GVCs_with_variants(+GenerationMode, ?GVCs)

augment_GVCs_with_variants/1 instantiates the variant argument of each gvc/3
term in GVCs with a list of variant (v/5) terms.  */

augment_GVCs_with_variants(GVCs) :-
	( generation_mode(dynamic) ->
	  augment_GVCs_with_variants_aux(GVCs, dynamic)
	; augment_GVCs_with_variants_aux(GVCs, static)
	).

%augment_GVCs_with_variants_quietly(GVCs) :-
%    augment_GVCs_with_variants(GVCs).

% Do not generate variants for words that are
% (1) invariant, or
% (2) only one or two characters long.

no_variants_word(Word, Category) :-
	( is_invariant_category(Category) ->
	  true
	  % At the LNCV meeting on 01/15/2009,
	  % we decided not to generate variants for words of 1 or 2 chars.
	; atom_codes(Word, WordChars),
	  length(WordChars, WordCharsLength),
	  WordCharsLength =< 2
	).

augment_GVCs_with_variants_aux([], _GenerationMode).
% Words of invariant category have no variants but themselves.
augment_GVCs_with_variants_aux([GVC|Rest], GenerationMode) :-
	GVC = gvc(Generator,Variants,_Candidates),
	Generator = v(Word,TempCategory,_,_,_,_),
	get_real_category(TempCategory, Category),
	( no_variants_word(Word, Category) ->
	  Variants = [Generator],
	  augment_variant_with_roots(Generator), % necessary?
	  augment_GVCs_with_variants_aux(Rest, GenerationMode)
	; augment_GVCs_with_variants_mode(GenerationMode, [GVC|Rest])
	).

augment_GVCs_with_variants_mode(static, [gvc(G,Vs,Cs)|Rest]) :-
	G = v(Generator,TempCategory,_,_,_,_),
	get_real_category(TempCategory, Category),
	% db_get_variants/3 takes as second argument either
	% a category (e.g., noun, verb, etc.), or [] (i.e., all categories)
	db_get_variants(Generator, Category, Vs0),
	( Vs0 == [] ->
	  augment_GVCs_with_variants_mode(dynamic, [gvc(G,Vs,Cs)])
	; Vs = Vs0
	),
	%    ((control_option(variants), QuietMode==non_quiet) ->
	%        with_output_to_chars(format('~p',[Categories]),StringCats),
	%        concatenate_items_to_atom([Generator," ",StringCats],GeneratorLabel),
	%        dump_variants_labelled(GeneratorLabel,Vs),
	%        format('~n',[])
	%    ;   true
	%    ),
	augment_GVCs_with_variants_aux(Rest, static).
augment_GVCs_with_variants_mode(dynamic, [gvc(G,Vs,_Cs)|Rest]) :-
	% augment the generator with acronyms, abbreviations and synonyms
	% temp
	G = v(Generator,_,_,_,_,_),
	%format('~a|2.00~n',[Generator]),
	compute_acros_abbrs(G,GAAs),
	announce_variants_length(Generator, 'GAAs', GAAs),
	% temp
	%format('~a|2.01~n',[Generator]),
	compute_syns(G,GSs),
	announce_variants_length(Generator, 'Gs', GSs),
	% temp
	%format('~a|2.02~n',[Generator]),
	% compute same-part, inflectional and derivational variants of G
	get_spid_variants(G,yes,GSPs,GIs,GDs),
	announce_variants_length(Generator, 'GSPs', GSPs),
	announce_variants_length(Generator, 'GIs', GIs),
	announce_variants_length(Generator, 'GDs', GDs),
	% temp
	%format('~a|2.03~n',[Generator]),
	% compute same-part, inflectional and derivational variants of AAs and Ss
	get_all_spid_variants(GAAs,no,GAASPs,GAAIs,GAADs),
	announce_variants_length(Generator, 'GAASPs', GAASPs),
	announce_variants_length(Generator, 'GAAIs', GAAIs),
	announce_variants_length(Generator, 'GAADs', GAADs),

	% temp
	%format('~a|2.04~n',[Generator]),
	get_all_spid_variants(GSs,no,GSSPs,GSIs,GSDs),
	announce_variants_length(Generator, 'GSSPs', GSSPs),
	announce_variants_length(Generator, 'GSIs', GSIs),
	announce_variants_length(Generator, 'GSDs', GSDs),
	% temp
	%format('~a|2.05~n',[Generator]),
	% compute synonyms of AAs and acronyms and abbreviations of Ss
	compute_all_syns(GAAs,GAASs),
	announce_variants_length(Generator, 'GAASs', GAASs),
	% temp
	%format('~a|2.06~n',[Generator]),
	compute_all_acros_abbrs(GSs,GSAAs),
	announce_variants_length(Generator, 'GSAAs', GSAAs),
	%temp
	%format('~a|2.07~n',[Generator]),
	% perform final augmentations
	% augment all derivational variants with synonyms and then inflect
	compute_synonyms_and_inflect(GDs,GDSIs),
	announce_variants_length(Generator, 'GDSIs', GDSIs),
	% temp
	%format('~a|2.08~n',[Generator]),
	compute_synonyms_and_inflect(GAADs,GAADSIs),
	announce_variants_length(Generator, 'GAADSIs', GAADSIs),
	% temp
	%format('~a|2.09~n',[Generator]),
	compute_synonyms_and_inflect(GSDs,GSDSIs),
	announce_variants_length(Generator, 'GSDSIs', GSDSIs),
	% temp
	%format('~a|2.10~n',[Generator]),
	% inflect acronym/abbreviation/synonym combinations (GAASs and GSAAs)
	compute_all_inflections(GAASs,GAASIs),
	announce_variants_length(Generator, 'GAASIs', GAASIs),
	% temp
	%format('~a|2.11~n',[Generator]),
	compute_all_inflections(GSAAs,GSAAIs),
	announce_variants_length(Generator, 'GSAAIs', GSAAIs),
	% temp
	%format('~a|2.12~n',[Generator]),
	% full_variants is obsolete
	%    (control_option(full_variants) ->
	%    format('~n',[]),
	%        dump_variants_labelled('G (A)',[G]),
	%        dump_variants_labelled('GAA (B)',GAAs),
	%        dump_variants_labelled('GS (C)',GSs),
	%        dump_variants_labelled('GSP (1)',GSPs),
	%        dump_variants_labelled('GI (2)',GIs),
	%        dump_variants_labelled('GD (3)',GDs),
	%        dump_variants_labelled('GAASP (4)',GAASPs),
	%        dump_variants_labelled('GAAI (5)',GAAIs),
	%        dump_variants_labelled('GAAD (6)',GAADs),
	%        dump_variants_labelled('GSSP (7)',GSSPs),
	%        dump_variants_labelled('GSI (8)',GSIs),
	%        dump_variants_labelled('GSD (9)',GSDs),
	%        dump_variants_labelled('GAAS (10)',GAASs),
	%        dump_variants_labelled('GSAA (11)',GSAAs),
	%        dump_variants_labelled('GDSI (12)',GDSIs),
	%        dump_variants_labelled('GAADSI (13)',GAADSIs),
	%        dump_variants_labelled('GSDSI (14)',GSDSIs),
	%        dump_variants_labelled('GAASI (15)',GAASIs),
	%        dump_variants_labelled('GSAAI (16)',GSAAIs),
	%        format('~n',[]),
	%    ;   true
	%    ),
	% merge all variants
	append([[G],GSPs,GIs,GDs,GDSIs,GAAs,GAASPs,GAAIs,GAADs,GAADSIs,
		GSs,GSSPs,GSIs,GSDs,GSDSIs,GAASs,GAASIs,GSAAs,GSAAIs],
	       Vs0),
	sort(Vs0, Vs1),
	glean_best_variants(Vs1,Vs),
	% temp
	%format('~a|2.13~n',[Generator]),
	augment_variants_with_roots(Vs),
	% temp
	%format('~a|2.14~n',[Generator]),
	%    ((control_option(variants), QuietMode==non_quiet) ->
	%        G=v(Generator,_,_,_,_,_),
	%        dump_variants_labelled(Generator,Vs),
	%        format('~n',[]),
	%    ;   true
	%    ),
	augment_GVCs_with_variants_aux(Rest, dynamic).
	
announce_variants_length(_Generator, _Type, _Data).

% announce_variants_length(Generator, Type, Data) :-
% 	length(Data, Length),
% 	( Length =\= 0 ->
% 	  format(user_output, '~q|~q|~d~n', [Generator,Type,Length])
% 	; true
% 	).
	       
get_real_category([],         []).
get_real_category([Category], Category).

/* is_invariant_category(?Category)
	
is_invariant_category/1 defines those Categories for which variant generation
should not be done.  */

is_invariant_category([]).
is_invariant_category(aux).
is_invariant_category(compl).
is_invariant_category(conj).
is_invariant_category(det).
is_invariant_category(modal).
is_invariant_category(prep).
is_invariant_category(pron).


/* compute_all_acros_abbrs(?Vs, -AAs)
   compute_all_acros_abbrs_aux(?Vs, -AALists)
   compute_acros_abbrs(?V, -AAs)

compute_all_acros_abbrs/2
compute_all_acros_abbrs_aux/2
compute_acros_abbrs/2
xxx
*/

compute_all_acros_abbrs([], []).
compute_all_acros_abbrs([H|T], AAs) :-
	compute_all_acros_abbrs_aux([H|T], AALists),
	append(AALists, AAs0),
	sort(AAs0, AAs).

compute_all_acros_abbrs_aux([], []).
compute_all_acros_abbrs_aux([V|Rest], [FirstAAList|RestAALists]) :-
	compute_acros_abbrs(V, FirstAAList),
	compute_all_acros_abbrs_aux(Rest, RestAALists).

compute_acros_abbrs(V,AAs) :-
    augment_variant_with_roots(V),
    V=v(_Word,Categories,VarLevel,History,Roots,_NFR),
    get_acros_abbrs(Roots,AAPairs0),
    filter_out_null_pairs(AAPairs0,AAPairs1),
    (History=="" ->
        AAPairs=AAPairs1
    ;   filter_out_expansions(AAPairs1,AAPairs)
    ),
    (AAPairs==[] ->
        AAs=[]
    ;   variant_score(acro_abbr,AcroAbbrLevel),
        NewVarLevel is VarLevel + AcroAbbrLevel,
        convert_aa_pairs_to_variants(AAPairs,Categories,NewVarLevel,History,AAs)
    ),
    !. % cut?
compute_acros_abbrs(_V,[]).


/* get_acros_abbrs+Atoms, -AAPairs)
   get_acros_abbrs_aux(+Atoms, -AAPairs)

get_acros_abbrs/2
get_acros_abbrs_aux/2
xxx
*/

get_acros_abbrs(Atoms, AAPairs) :-
	get_acros_abbrs_aux(Atoms, AAPairs0),
	sort(AAPairs0, AAPairs).

get_acros_abbrs_aux([], []).
get_acros_abbrs_aux([First|Rest], AAPairs) :-
	( control_option(unique_acros_abbrs_only) ->
	  db_get_unique_acros_abbrs(First, FirstAAPairs0)
	; db_get_all_acros_abbrs(First, FirstAAPairs0)
	),
	convert_aa_pairs(FirstAAPairs0, FirstAAPairs),
	append(FirstAAPairs, RestAAPairs, AAPairs),
	get_acros_abbrs_aux(Rest, RestAAPairs).


/* convert_aa_pairs(+AAQuads, -AAPairs)

convert_aa_pairs/2
xxx
*/

convert_aa_pairs([],[]).
convert_aa_pairs([LCTerm:TermType|Rest],
                 [LCTerm:TermTypeChar|ConvertedRest]) :-
    translate_aa_type(TermType,TermTypeChar),
    convert_aa_pairs(Rest,ConvertedRest).


/* translate_aa_type(?TermType, ?TermTypeChar)

translate_aa_type/2
xxx
*/

translate_aa_type(a, 0'a).
translate_aa_type(e, 0'e).


/* augment_variants_with_roots(?Vs)
   augment_variant_with_roots(?V)
   augment_generators_with_roots(?GVCs)

augment_variants_with_roots/1 uses augment_variant_with_roots/1 on each V of Vs.
augment_variant_with_roots/1 instantiates (if necessary) the Roots argument of V
which is of the form v(Word,Categories,VarLevel,History,Roots,NFR).
augment_generators_with_roots/1 instantiates each G in GVCs. */

% This is used only in dynamic mode
augment_variants_with_roots([]).
augment_variants_with_roots([First|Rest]) :-
	augment_variant_with_roots(First),
	augment_variants_with_roots(Rest).

%augment_variant_with_roots(v(Word,_Categories,_VarLevel,_History,Roots,_NFR)) :-
%    var(Roots),
%    !,
%    (lex_form_ci_recs(Word,LexRecords) ->
%        add_root_forms(LexRecords,[],Roots0),
%        lowercase_list(Roots0,Roots1),
%        sort(Roots1,Roots)
%    ;   Roots=[]
%    ).
%augment_variant_with_roots(_V).

%% temp
augment_variant_with_roots(v(Word,Categories,_VarLevel,_History,Roots,_NFR)) :-
	( var(Roots) ->
	  get_roots_for_word(Word, Categories, Roots)
	; true
	).

get_roots_for_word(Word, Categories, Roots) :-
	( get_base_forms_for_form(Word, Categories, Roots0) ->
	  lowercase_list(Roots0, Roots1),
	  sort(Roots1, Roots)
	; Roots=[]
	).

%% dump version
%augment_variant_with_roots(v(Word,Categories,_VarLevel,_History,Roots,_NFR)) :-
%    var(Roots),
%    !,
%    format('*|2.0|augment_variant_with_roots|~p~n',[Word]),
%    (get_base_forms_for_form(Word,Categories,Roots0) ->
%	format('*|2.1|get_base_forms_for_form|~p|~p|~p~n',[Word,Categories,Roots0]),
%        lowercase_list(Roots0,Roots1),
%        sort(Roots1,Roots)
%    ;   Roots=[]
%    ).
%augment_variant_with_roots(_V).

augment_generators_with_roots([]).
augment_generators_with_roots([gvc(G,_,_)|RestGVCs]) :-
	G =  v(_Word,_Categories,_VarLevel,_History,_Roots,_NFR),
	augment_variant_with_roots(G),
	augment_generators_with_roots(RestGVCs).


/* filter_out_null_pairs(+AAPairs, -FilteredAAPairs)

filter_out_null_pairs/2
xxx
*/

filter_out_null_pairs([],[]).
filter_out_null_pairs([First|Rest],Result) :-
    (First=['',_] ->
        Result=FilteredRest
    ;   Result=[First|FilteredRest]
    ),
    filter_out_null_pairs(Rest,FilteredRest).


/* filter_out_expansions(+AAPairs, -FilteredAAPairs)

filter_out_expansions/2
xxx
*/

filter_out_expansions([],[]).
filter_out_expansions([First|Rest],Result) :-
    (First=[_AA,0'x] ->   % '
        Result=FilteredRest
    ;   Result=[First|FilteredRest]
    ),
    filter_out_expansions(Rest,FilteredRest).


/* convert_aa_pairs_to_variants(+AAPairs, +Categories, +VarLevel, +History, -Vs)
   convert_aa_pair_to_variant(+AAPair, +Categories, +VarLevel, +History, -V)

convert_aa_pairs_to_variants/5
convert_aa_pair_to_variant/5
xxx
*/

convert_aa_pairs_to_variants([],_Categories,_VarLevel,_History,[]).
convert_aa_pairs_to_variants([First|Rest],Categories,VarLevel,History,
                             [ConvertedFirst|ConvertedRest]) :-
    convert_aa_pair_to_variant(First,Categories,VarLevel,History,
			       ConvertedFirst),
    convert_aa_pairs_to_variants(Rest,Categories,VarLevel,History,
				 ConvertedRest).

convert_aa_pair_to_variant(AA:Type,Categories,VarLevel,History,V) :-
    NewHistory=[Type|History],
    convert_to_variants([AA],Categories,VarLevel,NewHistory,[V]).


/* compute_all_syns(?Vs, -Ss)
   compute_all_syns_aux(?Vs, -SLists)
   compute_syns(+V, -Ss)
   compute_syns(+Vs, +SynonymLevel, +FilterIn, -FilterOut, +SynonymsIn,
                -SynonymsOut)

compute_all_syns/2
compute_all_syns_aux/2
compute_syns/2
compute_syns/6
xxx
*/

compute_all_syns([], []).
compute_all_syns([H|T], Ss) :-
	compute_all_syns_aux([H|T], SLists),
	append(SLists, Ss0),
	sort(Ss0, Ss).

compute_all_syns_aux([], []).
compute_all_syns_aux([V|Rest], [FirstSList|RestSLists]) :-
	compute_syns(V, FirstSList),
	compute_all_syns_aux(Rest, RestSLists).

compute_syns(V, Ss) :-
	augment_variant_with_roots(V),
	variant_score(synonym, SynonymLevel),
	compute_syns([V], SynonymLevel, [V], _FilterOut, [], Ss).

compute_syns([], _SynonymLevel, FilterIn, FilterIn, SynonymsIn, SynonymsIn).
compute_syns([V|Rest], SynonymLevel, FilterIn, FilterOut, SynonymsIn, SynonymsOut) :-
	augment_variant_with_roots(V),
	V = v(Word,Categories,VarLevel,History,Roots0,_NFR),
	( Roots0 == [] ->
	  Roots = [Word]
	; Roots = Roots0
	),
	get_synonym_pairs(Roots, Categories, SynonymPairs),
	NewVarLevel is VarLevel + SynonymLevel,
	NewHistory=[0's|History],
	convert_to_variants(SynonymPairs, NewVarLevel, NewHistory, Synonyms0),
	filter_by_var_level(Synonyms0, Synonyms1, FilterIn, FilterInOut0),
	append(SynonymsIn, Synonyms1, SynonymsInOut),
	append(FilterInOut0, Synonyms1, FilterInOut),
	append(Synonyms1, Rest, NewRest),
	compute_syns(NewRest, SynonymLevel, FilterInOut, FilterOut, SynonymsInOut, SynonymsOut).


/* get_synonym_pairs(+Atoms, +Categories, -Synonyms)
   get_synonym_pairs_aux(+Atoms, +Categories, -Synonyms)

get_synonym_pairs/3
get_synonym_pairs_aux/3
xxx
*/

get_synonym_pairs(Atoms,Categories,Synonyms) :-
    get_synonym_pairs_aux(Atoms,Categories,Synonyms0),
    sort(Synonyms0,Synonyms).

get_synonym_pairs_aux([],_,[]).
get_synonym_pairs_aux([First|Rest],Categories,Synonyms) :-
    (Categories=[Category] ->
	db_get_synonyms(First,Category,FirstSynonyms)
    ;   db_get_synonyms(First,FirstSynonyms)
    ),
    append(FirstSynonyms,RestSynonyms,Synonyms),
    get_synonym_pairs_aux(Rest,Categories,RestSynonyms).


/* convert_to_variants(+Pairs, +VarLevel, +History, -Variants)
   convert_to_variants(+Atoms, +Categories, +VarLevel, +History, -Variants)

convert_to_variants/4
convert_to_variants/5
xxx
Pairs is a list of Word-Category pairs.
*/

convert_to_variants([], _VarLevel, _History, []).
convert_to_variants([First-Category|Rest], VarLevel, History,
                    [v(First,[Category],VarLevel,History,_,_)|ConvertedRest]) :-
	convert_to_variants(Rest, VarLevel, History, ConvertedRest).

convert_to_variants([], _Categories, _VarLevel, _History, []).
convert_to_variants([First|Rest], Categories, VarLevel, History,
                    [v(First,Categories,VarLevel,History,_,_)|ConvertedRest]) :-
	convert_to_variants(Rest, Categories, VarLevel, History, ConvertedRest).


/* filter_by_var_level(+VsIn, -VsOut, +FilterIn, -FilterOut)
   filter_by_var_level_aux(+FilterIn, +V, -FilterOut, -Keep)

filter_by_var_level/4
filter_by_var_level_aux/4
xxx
*/
% cuts?
filter_by_var_level([], [], FilterIn, FilterIn).
filter_by_var_level([V|Rest], FilteredResult, FilterIn, FilterOut) :-
	filter_by_var_level_aux(FilterIn, V, FilterInOut, Keep),
	( Keep == keep ->
	  FilteredResult = [V|FilteredRest]
	; FilteredResult = FilteredRest
	),
	filter_by_var_level(Rest, FilteredRest, FilterInOut, FilterOut).

filter_by_var_level_aux([], _V, [], keep).
filter_by_var_level_aux([First|Rest], V, [NewFirst|Rest], nokeep) :-
	% if the new variation is better than a filter variation,
	% modify the filter list and discard the new variation
	V = v(Word,Categories,VarLevel,History,VRoots,NFR),
	First = v(Word,Categories,FilterVarLevel,_FirstHistory,FirstRoots,_FirstNFR),
	VarLevel < FilterVarLevel,
	( \+var(FirstRoots) ->
	   Roots = FirstRoots
	; \+var(VRoots) ->
	  Roots = VRoots
	; true
	),
	NewFirst = v(Word,Categories,VarLevel,History,Roots,NFR),
	!.
filter_by_var_level_aux([First|Rest], V, [NewFirst|Rest], nokeep) :-
	% if the new variation is not better than a filter variation,
	% discard the new one
	V = v(Word,_,_,_,VRoots,_),
	First = v(Word,Categories,VarLevel,History,_,NFR),
	( var(VRoots) ->
	  NewFirst = First
	; NewFirst = v(Word,Categories,VarLevel,History,VRoots,NFR)
	),
	!.
filter_by_var_level_aux([First|Rest], V, [First|FilteredRest], Keep) :-
	% otherwise, continue to search for a matching filter variation
	filter_by_var_level_aux(Rest, V, FilteredRest, Keep).

/* qword_has_roots(+QWord, -Roots)

qword_has_roots/2
xxx
*/

%qword_has_roots([_Atom,_Categories,_VarLevel,_History,Roots],Roots).


/* variant_has_roots(+V, -Roots)

variant_has_roots/2
xxx
*/

%variant_has_roots(v(_Word,_Categories,_VarLevel,_History,Roots,_NFR),Roots) :-
%    \+var(Roots).


/* get_all_spid_variants(+Vs, +SPFlag, -SPVariants, -IVariants, -DVariants)

get_all_spid_variants/5
xxx
*/

get_all_spid_variants([],_SPFlag,[],[],[]).
get_all_spid_variants([First|Rest],SPFlag,SPVariants,IVariants,DVariants) :-
    get_spid_variants(First,SPFlag,FirstSPVariants,FirstIVariants,
                              FirstDVariants),
    append(FirstSPVariants,RestSPVariants,SPVariants),
    append(FirstIVariants,RestIVariants,IVariants),
    append(FirstDVariants,RestDVariants,DVariants),
    get_all_spid_variants(Rest,SPFlag,RestSPVariants,RestIVariants,
                          RestDVariants).


/* get_spid_variants(+V, +SPFlag, -SPVariants, -IVariants, -DVariants)

get_spid_variants/5
xxx
*/

verify_base_form_and_history(History, Word) :-
	( History == [] ->
	  true
	; is_a_base_form(Word)
	).

%% temp
get_spid_variants(V,_SPFlag,SPVariants,IVariants,DVariants) :-
    variant_score(inflection,InflectionLevel),
    variant_score(spelling,SpellingLevel),
    variant_score(derivation,DerivationLevel),
    V=v(Word,Categories,VarLevel,History,_Roots,_NFR),
    % compute the sp_variants and i_variants
    ( ( verify_base_form_and_history(History, Word),
	get_spellings_and_inflections_for_form(Word,Categories,
					       SPVariantAtoms0,IVariantAtoms0) ) ->
        ord_subtract(IVariantAtoms0,SPVariantAtoms0,IVariantAtoms1),
        lowercase_list(SPVariantAtoms0,SPVariantAtoms1),
        sort(SPVariantAtoms1,SPVariantAtoms2),
        ord_subtract(SPVariantAtoms2,[Word],SPVariantAtoms),
        lowercase_list(IVariantAtoms1,IVariantAtoms2),
        sort(IVariantAtoms2,IVariantAtoms),
        (SPVariantAtoms==[] ->
            SPVariants=[]
        ;   NewSPVarLevel is VarLevel + SpellingLevel,
            NewSPHistory=[0'p|History],
            convert_to_variants(SPVariantAtoms,Categories,NewSPVarLevel,
				NewSPHistory,SPVariants)
        ),
        (IVariantAtoms==[] ->
            IVariants=[]
        ;   NewIVarLevel is VarLevel + InflectionLevel,
            NewIHistory=[0'i|History],
            convert_to_variants(IVariantAtoms,Categories,NewIVarLevel,
				NewIHistory,IVariants)
        ),
        % compute the d_variants
        % do not compute derivational variants for AAs (expansions are allowed)
        ((aao(Word); History=[0'a|_]) ->  %'
            DVariants=[]
        ;   get_all_derivational_variants(SPVariantAtoms2,IVariantAtoms,
	                                  Categories,VarLevel,History,
					  DerivationLevel,DVariants)
	)
    ;   SPVariants=[],
        IVariants=[],
        DVariants=[]
    ).

/* get_all_derivational_variants(+SPVariantAtoms, +IVariantAtoms, +Categories,
                                 +VarLevel, +History, +DerivationLevel,
                                 -DVariants)

get_all_derivational_variants/7 computes the set DVariants of derivational
variants of any of the words in SPVariantAtoms filtering on IVariantAtoms.
xxx
*/

%% temp
get_all_derivational_variants(SPVariantAtoms,IVariantAtoms,Categories,
                              VarLevel,History,DerivationLevel,DVariants) :-
    get_initial_root_forms(SPVariantAtoms,Categories,RootTerms0),
    filter_by_categories(RootTerms0,Categories,RootTerms1), % redundant now?
    convert_terms_to_variants(RootTerms1,VarLevel,History,Vs),
    extract_atoms_from_terms(RootTerms1,RootAtoms),
    append([RootAtoms,SPVariantAtoms,IVariantAtoms],FilterAtoms0),
    sort(FilterAtoms0,FilterAtoms),
    generate_derivational_root_forms(Vs,FilterAtoms,DerivationLevel,
                                     [],DVariants0),
    sort(DVariants0,DVariants).

/* get_initial_root_forms(+SPVariantAtoms, +Categories, -RootTerms)
   get_initial_root_forms(+SPVariantAtoms, +Categories,
                          +RootTermsIn, -RootTermsOut)

get_initial_root_forms/3
The elements of RootTerms are of the form Form:[cat:[Category]]
xxx
*/

get_initial_root_forms(SPVariantAtoms,Categories,RootTerms) :-
    get_initial_root_forms(SPVariantAtoms,Categories,[],RootTerms0),
    lowercase_terms(RootTerms0,RootTerms1),
    sort(RootTerms1,RootTerms).

get_initial_root_forms([],_Categories,RootTermsIn,RootTermsIn).
get_initial_root_forms([SPVariantAtom|Rest],Categories,
		       RootTermsIn,RootTermsOut) :-
    % Find the bases for the sp-variants
    get_bases(SPVariantAtom,Categories,BaseAtoms),
    generate_root_forms_from_bases(BaseAtoms,RootTerms0),
    append(RootTerms0,RootTermsIn,RootTermsInOut),
    get_initial_root_forms(Rest,Categories,RootTermsInOut,RootTermsOut).


/* get_bases(+WordAtom, +Categories, -BaseAtoms)

WARNING: base form here seems to mean citation form

get_bases/3
% cut?  Why is LexRecords quantified in bagof?  If lex_form_ci_recs never
%       returns [], then bagof will never fail; then use local cut
xxx
*/

%get_bases(WordAtom,Categories,BaseAtoms) :-
%    lex_form_ci_recs(WordAtom,LexRecords),
%    bagof(Base,
%          LexRecord^LexRecords^(member(LexRecord,LexRecords),
%                                lex_get_base_from_record(LexRecord,Base)),
%          BaseAtoms0),
%    !,
%    lowercase_list(BaseAtoms0,BaseAtoms1),
%    sort(BaseAtoms1,BaseAtoms).
%get_bases(_WordAtom,_Categories,[]).

%% temp
get_bases(WordAtom,Categories,BaseAtoms) :-
    get_citation_forms_for_form(WordAtom,Categories,BaseAtoms0),
    !,
    lowercase_list(BaseAtoms0,BaseAtoms1),
    sort(BaseAtoms1,BaseAtoms).
get_bases(_WordAtom,_Categories,[]).

%% dump version
%get_bases(WordAtom,Categories,BaseAtoms) :-
%    get_citation_forms_for_form(WordAtom,Categories,BaseAtoms0),
%    !,
%    format('*|4.1|get_bases|~p|~p|~p~n',[WordAtom,Categories,BaseAtoms0]),
%    lowercase_list(BaseAtoms0,BaseAtoms1),
%    sort(BaseAtoms1,BaseAtoms).
%get_bases(_WordAtom,[]).


/* generate_root_forms_from_bases(+BaseAtoms, -RootTerms)
   generate_root_forms_from_base(+BaseAtom, -RootTerms)

generate_root_forms_from_bases/2
xxx
*/

generate_root_forms_from_bases([],[]).
generate_root_forms_from_bases([First|Rest],RootTerms) :-
    generate_root_forms_from_base(First,FirstRootTerms),
    append(FirstRootTerms,RestRootTerms,RootTerms),
    generate_root_forms_from_bases(Rest,RestRootTerms).

%% temp
generate_root_forms_from_base(BaseAtom,RootTerms) :-
    get_variants_for_citation_form(BaseAtom,VariantList),
    extract_root_forms_from_variants(VariantList,RootTerms).

%% dump version
%generate_root_forms_from_base(BaseAtom,RootTerms) :-
%    get_variants_for_citation_form(BaseAtom,VariantList),
%    format('*|4.2|get_variants_for_citation_form|~p|~p~n',
%	   [BaseAtom,VariantList]),
%    extract_root_forms_from_variants(VariantList,RootTerms),
%    format('*|4.3|extract_root_forms_from_variants|~p|~p~n',
%	   [VariantList,RootTerms]).


/* extract_root_forms_from_variants(+VariantList, -RootTerms)

extract_root_forms_from_variants/2
xxx
*/

extract_root_forms_from_variants([],[]).
extract_root_forms_from_variants([Form:[Category:[base]]|Rest],
                                  [Form:[cat:[Category]]|ExtractedRest]) :-
    !,
    extract_root_forms_from_variants(Rest,ExtractedRest).
extract_root_forms_from_variants([Form:[Category:[spvar]]|Rest],
                                  [Form:[cat:[Category]]|ExtractedRest]) :-
    !,
    extract_root_forms_from_variants(Rest,ExtractedRest).
extract_root_forms_from_variants([_First|Rest],ExtractedRest) :-
    extract_root_forms_from_variants(Rest,ExtractedRest).


/* lowercase_terms(+Term, -LCTerm)

lowercase_terms/2
xxx
*/

lowercase_terms([],[]).
lowercase_terms([Form:Info|Rest],[LCForm:Info|LCRest]) :-
    lower(Form,LCForm),
    lowercase_terms(Rest,LCRest).


/* filter_by_categories(+RootTerms, +Categories, -FilteredRootTerms)

filter_by_categories/2
xxx
*/

filter_by_categories(RootTerms,[],RootTerms) :-
    !.
filter_by_categories([],_,[]).
filter_by_categories([First|Rest],Categories,Result) :-
    First=_Form:[cat:[Category]],
    (member(Category,Categories) ->
        Result=[First|FilteredRest]
    ;   Result=FilteredRest
    ),
    filter_by_categories(Rest,Categories,FilteredRest).


/* convert_terms_to_variants(+Terms, +VarLevel, +History, -Variants)

convert_terms_to_variants/4 converts terms of the form Form:[cat:Categories]
to variants of the form v(Form,Categories,VarLevel,History,_,_).
*/

convert_terms_to_variants([],_VarLevel,_History,[]).
convert_terms_to_variants([Form:[cat:Categories]|Rest],VarLevel,History,
                         [v(Form,Categories,VarLevel,History,_,_)
                          |ConvertedRest]) :-
    convert_terms_to_variants(Rest,VarLevel,History,ConvertedRest).


/* extract_atoms_from_terms(+Terms, -Atoms)

extract_atoms_from_terms/2
xxx
*/

extract_atoms_from_terms([],[]).
extract_atoms_from_terms([Form:_Info|Rest],
                         [Form|ExtractedRest]) :-
    extract_atoms_from_terms(Rest,ExtractedRest).


/* generate_derivational_root_forms(+GVs, +FilterAtoms, +DerivationLevel,
                                    +VsIn, -VsOut)

generate_derivational_root_forms/5
xxx
*/

generate_derivational_root_forms([],_,_,VsIn,VsIn).
generate_derivational_root_forms([FirstV|RestVs],FilterAtoms,DerivationLevel,
                                 VsIn,VsOut) :-
    FirstV=v(Form,Categories,VarLevel,History,_Roots,_NFR),
    get_dm_variant_terms(Form:[cat:Categories],NewVTerms0),
    filter_terms_by_atoms(NewVTerms0,FilterAtoms,NewVTerms1),
%format('gdrfc: ~a ~p -> ~p~n',[Form,Categories,NewVTerms1]),
    filter_derivational_terms(NewVTerms1,Form,NewVTerms),
    NewVarLevel is VarLevel + DerivationLevel,
    NewHistory=[0'd|History],
    convert_terms_to_variants(NewVTerms,NewVarLevel,NewHistory,NewVs),
    extract_atoms_from_terms(NewVTerms,NewVAtoms),
    append(RestVs,NewVs,NewGVs),
    append(FilterAtoms,NewVAtoms,NewFilterAtoms),
    append(VsIn,NewVs,VsInOut),
    generate_derivational_root_forms(NewGVs,NewFilterAtoms,DerivationLevel,
                                     VsInOut,VsOut).


/* get_dm_variant_terms(+VariantTerm, -DVariantTerms)

get_dm_variant_terms/2
xxx
*/

%% temp
get_dm_variant_terms([],[]).
get_dm_variant_terms(Form:[cat:Categories],DVariantTerms) :-
    get_dm_variants(Form,Categories,DVariantTerms0),
    filter_root_forms_to_base_with_categories(DVariantTerms0,
                                              DVariantTerms1),
    ( \+ control_option(all_derivational_variants) ->
      filter_an_variants(DVariantTerms1,Categories,DVariantTerms)
    ; DVariantTerms=DVariantTerms1
    ).

%% dump version
%get_dm_variant_terms([],[]).
%get_dm_variant_terms(Form:[cat:Categories],DVariantTerms) :-
%    format('*|5.0|get_dm_variant_terms|~p~n',[Form:[cat:Categories]]),
%    get_dm_variants(Form,Categories,DVariantTerms0),
%    filter_root_forms_to_base_with_categories(DVariantTerms0,
%                                              DVariantTerms1),
%    (control_option(an_derivational_variants) ->
%	filter_an_variants(DVariantTerms1,Categories,DVariantTerms)
%    ;   DVariantTerms=DVariantTerms1
%    ),
%    format('*|5.9|get_dm_variant_terms|~p|~p~n',
%	   [Form:[cat:Categories],DVariantTerms]).


/* get_dm_variants(+WordAtom, +Categories, -DVariantTerms)

get_dm_variants/3
xxx
*/

%% temp
get_dm_variants(WordAtom,Categories,VariantTerms) :-
    (get_derivational_variants_for_form(WordAtom,Categories,VariantTerms0) ->
        filter_out_null_terms(VariantTerms0,VariantTerms)
    ;   VariantTerms=[]
    ).

%% dump version
%get_dm_variants(WordAtom,Categories,VariantTerms) :-
%    (get_derivational_variants_for_form(WordAtom,Categories,VariantTerms0) ->
%	format('*|5.1|get_derivational_variants_for_form|~p|~p|~p~n',
%	      [WordAtom,Categories,VariantTerms0]),
%        filter_out_null_terms(VariantTerms0,VariantTerms)
%    ;   VariantTerms=[]
%    ).

% this should be temporary since dm_variants/3 should never return a null term
filter_out_null_terms([],[]).
filter_out_null_terms(['':_|Rest],Result) :-
    !,
    filter_out_null_terms(Rest,Result).
filter_out_null_terms([First|Rest],[First|FilteredRest]) :-
    filter_out_null_terms(Rest,FilteredRest).


/* filter_root_forms_to_base_with_categories(+Terms, -FilteredTerms)

filter_root_forms_to_base_with_categories/2 returns FilteredTerms, those
elements of Terms which are base forms with the given categories. */

%% temp
filter_root_forms_to_base_with_categories([],[]).
filter_root_forms_to_base_with_categories([Form:[cat:Categories]|Rest],
                                          Result) :-
    (is_a_base_form_with_categories(Form,Categories) ->
        lower(Form,LCForm),
        Result=[LCForm:[cat:Categories]|FilteredRest]
    ;   Result=FilteredRest
    ),
    filter_root_forms_to_base_with_categories(Rest,FilteredRest).

%% dump version
%filter_root_forms_to_base_with_categories([],[]).
%filter_root_forms_to_base_with_categories([Form:[cat:Categories]|Rest],
%                                          Result) :-
%    (is_a_base_form_with_categories(Form,Categories) ->
%	format('*|5.2|is_a_base_form_with_categories|~p|~p|true~n',
%	       [Form,Categories]),
%        lower(Form,LCForm),
%        Result=[LCForm:[cat:Categories]|FilteredRest]
%    ;   Result=FilteredRest
%    ),
%    filter_root_forms_to_base_with_categories(Rest,FilteredRest).


/* filter_an_variants(+DVariantTermsIn, +Categories, -DVariantTermsOut)
   filter_an_variants_aux(+DVariantTermsIn, +VariantCategories,
   -DVariantTermsOut)

filter_an_variants/3 filters adjective/noun variants. Categories must be
either [noun] or [adj]. If it is [noun], then DVariantTermsOut will contain
only those DVariantTermsIn with category [adj]; if it is [adj] then the
filtered terms must have category [noun]. */

filter_an_variants(DVariantTermsIn,Categories,DVariantTermsOut) :-
    Categories=[_Singleton],
    !,
    (   Categories==[noun] ->
	filter_an_variants_aux(DVariantTermsIn,[adj],DVariantTermsOut)
    ;   Categories==[adj] ->
	filter_an_variants_aux(DVariantTermsIn,[noun],DVariantTermsOut)
    ;	DVariantTermsOut=[]
    ).
filter_an_variants(_DVariantTermsIn,Categories,[]) :-
    format('~NERROR: filter_an_variants/3 found non-singleton categories: ~p~n',
	   [Categories]).

filter_an_variants_aux([],_,[]) :-
    !.
filter_an_variants_aux([First|Rest],VariantCategories,[First|FilteredRest]) :-
    First=_Form:[cat:VariantCategories],
    !,
    filter_an_variants_aux(Rest,VariantCategories,FilteredRest).
filter_an_variants_aux([_|Rest],VariantCategories,FilteredRest) :-
    filter_an_variants_aux(Rest,VariantCategories,FilteredRest).


/* filter_terms_by_atoms(+Terms, +Atoms, -FilteredTerms)

filter_terms_by_atoms/3
xxx
NOT MEMBER
*/

filter_terms_by_atoms([],_Atoms,[]).
filter_terms_by_atoms([First|Rest],Atoms,Result) :-
    First=Form:_Info,
    (member(Form,Atoms) ->
        Result=FilteredRest
    ;   Result=[First|FilteredRest]
    ),
    filter_terms_by_atoms(Rest,Atoms,FilteredRest).


/* filter_derivational_terms(+DVariantTerms, +Form, -FilteredDVariantTerms)

filter_derivational_terms/3 filters out DVariantTerms which are either AAs
only or which are explicitly excluded by vdx/2.  */

filter_derivational_terms([],_,[]).
filter_derivational_terms([DForm:_|Rest],Form,FilteredRest) :-
    (aao(DForm); vdx(Form,DForm)),
    !,
%format('dx:~a -> ~a~n',[Form,DForm]),
    filter_derivational_terms(Rest,Form,FilteredRest).
filter_derivational_terms([First|Rest],Form,[First|FilteredRest]) :-
    filter_derivational_terms(Rest,Form,FilteredRest).


/* translate_variant_terms(+VariantTerms, -Variants)

translate_variant_terms/2
xxx
*/

translate_variant_terms([],[]).
translate_variant_terms([Form:[Category:_]|Rest],
                                  [Form:[cat:[Category]]|TranslatedRest]) :-
    translate_variant_terms(Rest,TranslatedRest).


/* filter_forms_by_categories(+Terms, +Categories, -FilterTerms)

filter_forms_by_categories/3
xxx
*/

filter_forms_by_categories(X,[],X) :-
    !.
filter_forms_by_categories([],_Categories,[]).
filter_forms_by_categories([Form:[cat:FormCategories]|Rest],Categories,
                           Result) :-
    intersection(FormCategories,Categories,FilteredCategories),
    (FilteredCategories\==[] ->
        Result=[Form:[cat:FilteredCategories]|FilteredRest]
    ;   Result=FilteredRest
    ),
    filter_forms_by_categories(Rest,Categories,FilteredRest).


/* compute_synonyms_and_inflect(+Vs, -SIVs)
   compute_synonyms_and_inflect_aux(+Vs, +InflectionLevel, -SIVLists)

compute_synonyms_and_inflect/2
compute_synonyms_and_inflect_aux/2
xxx
*/

compute_synonyms_and_inflect([], []).
compute_synonyms_and_inflect([H|T], SIVs) :-
	variant_score(inflection, InflectionLevel),
	compute_synonyms_and_inflect_aux([H|T], InflectionLevel, SIVLists),
	append(SIVLists, SIVs).

compute_synonyms_and_inflect_aux([], _InflectionLevel, []).
compute_synonyms_and_inflect_aux([V|Rest], InflectionLevel, [SIVs|RestSIVs]) :-
	get_synonyms_for_variant(V, SVs0),
	SVs = [V|SVs0],
	compute_all_inflections(SVs, InflectionLevel, SIVs0),
	append(SVs0, SIVs0, SIVs),
	compute_synonyms_and_inflect_aux(Rest, InflectionLevel, RestSIVs).

/* get_synonyms_for_variant(+V, -VSynonyms)
   get_synonyms_for_variant(+V, +SynonymLevel, +FilterIn, -FilterOut,
                           +VSynonymsIn, -VSynonymsOut)

get_synonyms_for_variant/2
get_synonyms_for_variant/6
xxx
*/

get_synonyms_for_variant(V,VSynonyms) :-
    variant_score(synonym,SynonymLevel),
    get_synonyms_for_variant([V],SynonymLevel,[V],_FilterOut,
                            [],VSynonyms).

get_synonyms_for_variant([],_SynonymLevel,FilterIn,FilterIn,
                        SynonymsIn,SynonymsIn).
get_synonyms_for_variant([V|Rest],SynonymLevel,FilterIn,FilterOut,
                        SynonymsIn,SynonymsOut) :-
    augment_variant_with_roots(V),
    V=v(Atom,Categories,VarLevel,History,Roots0,_NFR),
    (Roots0==[] ->
        Roots=[Atom]
    ;   Roots=Roots0
    ),
    get_synonym_pairs(Roots,Categories,SynonymPairs),
    NewVarLevel is VarLevel + SynonymLevel,
    NewHistory=[0's|History],
    convert_to_variants(SynonymPairs,NewVarLevel,NewHistory,Synonyms0),
    filter_by_var_level(Synonyms0,Synonyms1,FilterIn,FilterInOut0),
    append(SynonymsIn,Synonyms1,SynonymsInOut),
    append(FilterInOut0,Synonyms1,FilterInOut),
    append(Synonyms1,Rest,NewRest),
    get_synonyms_for_variant(NewRest,SynonymLevel,FilterInOut,FilterOut,
                            SynonymsInOut,SynonymsOut).


/* compute_all_inflections(+Vs, -IVs)
   compute_all_inflections(+Vs, +InflectionLevel, -IVs)

compute_all_inflections/2
compute_all_inflections/3
xxx
*/

compute_all_inflections([], []).
compute_all_inflections([H|T], IVs) :-
	variant_score(inflection, InflectionLevel),
	compute_all_inflections([H|T], InflectionLevel, IVs).

%% temp
compute_all_inflections([],_InflectionLevel,[]).
compute_all_inflections([V|Rest],InflectionLevel,IVs) :-
    inflect_variant(V,IAtoms),
    V=v(_Atom,Categories,VarLevel,History,_Roots,_NFR),
    NewVarLevel is VarLevel + InflectionLevel,
    NewHistory=[0'i|History],
    convert_to_variants(IAtoms,Categories,NewVarLevel,NewHistory,IVs0),
    append(IVs0,RestIVs,IVs),
    compute_all_inflections(Rest,InflectionLevel,RestIVs).

%% dump version
%compute_all_inflections([],_InflectionLevel,[]).
%compute_all_inflections([V|Rest],InflectionLevel,IVs) :-
%    inflect_variant(V,IAtoms),
%    V=v(Atom,Categories,VarLevel,History,_Roots,_NFR),
%    format('*|6.0|compute_all_inflections|~p|~p|~p~n',
%	   [Atom,Categories,IAtoms]),
%    NewVarLevel is VarLevel + InflectionLevel,
%    NewHistory=[0'i|History],
%    convert_to_variants(IAtoms,Categories,NewVarLevel,NewHistory,IVs0),
%    append(IVs0,RestIVs,IVs),
%    compute_all_inflections(Rest,InflectionLevel,RestIVs).


/* inflect_variant(+V, -InflectedWords)

inflect_variant/2
xxx
*/

%% temp
inflect_variant(v(Word,Categories,_VarLevel,_History,_Roots,_NFR),
                InflectedWords) :-
    (get_variants_for_form(Word,VariantTerms0) ->
        translate_variant_terms(VariantTerms0,VariantTerms1),
        filter_forms_by_categories(VariantTerms1,Categories,VariantTerms2),
        extract_atoms_from_terms(VariantTerms2,InflectedWords0),
        lowercase_list(InflectedWords0,InflectedWords1),
        sort(InflectedWords1,InflectedWords2),
        ord_subtract(InflectedWords2,[Word],InflectedWords)
    ;   InflectedWords=[]
    ).

%% dump version
%inflect_variant(v(Word,Categories,_VarLevel,_History,_Roots,_NFR),
%                InflectedWords) :-
%    (get_variants_for_form(Word,VariantTerms0) ->
%	format('*|6.1|get_variants_for_form|~p|~p~n',[Word,VariantTerms0]),
%        translate_variant_terms(VariantTerms0,VariantTerms1),
%        filter_forms_by_categories(VariantTerms1,Categories,VariantTerms2),
%        extract_atoms_from_terms(VariantTerms2,InflectedWords0),
%        lowercase_list(InflectedWords0,InflectedWords1),
%        sort(InflectedWords1,InflectedWords2),
%        ord_subtract(InflectedWords2,[Word],InflectedWords)
%    ;   InflectedWords=[]
%    ).


/* glean_best_variants(+SortedVs, -GleanedVs)

glean_best_variants/2
xxx
*/

glean_best_variants([], []).
glean_best_variants([H|T], BestVariants) :-
	glean_best_variants_1(T, H, BestVariants).

glean_best_variants_1([], Singleton, [Singleton]).
glean_best_variants_1([V2|Rest], V1, GleanedVs) :-
	% enforce category
	% V1 = v(Word,_,VarLevel1,_,_,_),
	% V2 = v(Word,_,VarLevel2,_,_,_),
	V1 = v(Word,Categories,VarLevel1,_,_,_),
	V2 = v(Word,Categories,VarLevel2,_,_,_),
	!,
	( VarLevel1 < VarLevel2 ->
	  Best = V1
	; Best = V2
	),
	glean_best_variants_1(Rest, Best, GleanedVs).
glean_best_variants_1([Next|Rest], First, [First|GleanedRest]) :-
	glean_best_variants_1(Rest, Next, GleanedRest).


/* gather_variants(+GVCs, +PhraseWords, +HeadWords, -VAVL)
   gather_variants_GVC(+GVCs, +PhraseWords, +HeadPosition, +VAVLIn, -VAVLOut)
   gather_variants_pos(+GeneratorPositions, +PhraseWords, +HeadPosition, +Generator,
   		     +Vs, +NFR, +VAVLIn, -VAVLOut)
   gather_variants_var(+Vs, +NFR, +Generator, +GeneratorPosition,
                     +GeneratorInvolvesHead, +VAVLIn, -VAVLOut)
CAREFUL!!!

gather_variants/4
gather_variants_GVC/5
gather_variants_var/7
gather_variants_pos/8

*/

gather_variants(GVCs, PhraseWords, HeadWords, VariantsAVL) :-
	empty_avl(EmptyVariantsAVL),
	empty_avl(EmptyPositionAVL),
	compute_all_subsequence_positions(HeadWords, PhraseWords, PossibleHeadPositions),
	concatenate_text(HeadWords, ' ', HeadWordsAtom),
	add_to_avl_once(HeadWordsAtom, PossibleHeadPositions,
			EmptyPositionAVL, InitialPositionAVL),
	% reversed order of args from QP library version!
	last(PossibleHeadPositions, HeadPosition),
	gather_variants_GVC(GVCs, PhraseWords, HeadPosition,
			    InitialPositionAVL,
			    EmptyVariantsAVL, VariantsAVL).

% Loop through all gvc/3 terms, and for each gvc/3 term,
% loop through all positions of the GeneratorWord in the phrase.
gather_variants_GVC([],_PhraseWords, _HeadPosition, _PositionAVL, VAVLIn, VAVLIn).
gather_variants_GVC([gvc(Generator,Variants,_)|Rest], PhraseWords, HeadPosition,
		    PositionAVLIn, VAVLIn, VAVLOut) :-
	Generator = v(GeneratorWord,_LexCats,_,_,_,NFR),
	% format(user_output, 'GVC: ~q-~q~n', [GeneratorWord,LexCats]),
	tokenize_text_mm_lc(GeneratorWord, GeneratorWordList),
	cached_compute_all_subsequence_positions(GeneratorWord, GeneratorWordList,
						 PhraseWords, GeneratorPositions,
						 PositionAVLIn, PositionAVLOut),
	GeneratorPositions = [[FirstI|_]|_],
	length(PhraseWords, PhraseWordsLength),
	% instantiate NFR here!
	NFR is PhraseWordsLength + 1 - FirstI,
	gather_variants_pos(GeneratorPositions, PhraseWords, HeadPosition,
			    Generator, Variants, NFR, VAVLIn, VAVLInOut),
	gather_variants_GVC(Rest, PhraseWords, HeadPosition, PositionAVLOut, VAVLInOut, VAVLOut).

% For each generator position in the phrase words, loop through all the variants.
gather_variants_pos([], _PhraseWords, _HeadPosition, _Generator, _Variants, _NFR, VAVLIn, VAVLIn).
gather_variants_pos([GeneratorPosition|Rest], PhraseWords, HeadPosition, Generator,
		  Variants, NFR,VAVLIn, VAVLOut) :-
	% format(user_output, '   POS: ~q~n', [GeneratorPosition]),
	compute_head_involvement(GeneratorPosition, HeadPosition, GeneratorInvolvesHead),
	gather_variants_var(Variants, NFR, Generator,
			    GeneratorPosition, GeneratorInvolvesHead,
			    VAVLIn, VAVLInOut),
	gather_variants_pos(Rest, PhraseWords, HeadPosition, Generator,
			    Variants, NFR, VAVLInOut, VAVLOut).

% For each v/6 variant in the V part of gvc(G,V,C),
gather_variants_var([], _NFR, _Generator, _GeneratorPosition, _GeneratorInvolvesHead, VAVLIn, VAVLIn).
gather_variants_var([Variant|RestVariants], NFR, Generator,
		    GeneratorPosition, GeneratorInvolvesHead, VAVLIn, VAVLOut) :-
	% instantiate NFR!
	Variant = v(Word,_,_,_,_,NFR),
	tokenize_text_mm_lc(Word, Words),
	VInfo = vinfo(Generator,GeneratorPosition,GeneratorInvolvesHead,Variant,Words),
	( Words = [FirstWord|_] ->
	  % format(user_output, '      VAR: ~q:~q~n', [FirstWord,VInfo]),
	  add_to_avl(FirstWord, VInfo, VAVLIn, VAVLInOut)
	; abort,
	  VAVLInOut = VAVLIn
	),
	gather_variants_var(RestVariants, NFR, Generator, GeneratorPosition,
			    GeneratorInvolvesHead, VAVLInOut, VAVLOut).

% First check the cache to see if we have already computed
% the subsequence positions for this word sequence.
cached_compute_all_subsequence_positions(GeneratorAtom, GeneratorWordList,
					 PhraseWords, GeneratorPositions,
					 PositionAVLIn, PositionAVLOut) :-
	% avl:avl_size(PositionAVLIn, PositionAVLSize),
	% GeneratorAtom = GeneratorWordList,
	( avl_fetch(GeneratorAtom, PositionAVLIn, [GeneratorPositions]) ->
	  % format(user_output, '~n    Cached (~w): ~q|~q|~q~n',
	  % 	 [PositionAVLSize, GeneratorWordList, PhraseWords, GeneratorPositions]),
	  PositionAVLOut = PositionAVLIn
	; compute_all_subsequence_positions(GeneratorWordList, PhraseWords, GeneratorPositions),
	  % format(user_output, '~nNot Cached (~w): ~q|~q|~q~n',
	  % 	 [PositionAVLSize, GeneratorWordList, PhraseWords, GeneratorPositions]),
	  add_to_avl_once(GeneratorAtom, GeneratorPositions, PositionAVLIn, PositionAVLOut)
	).

compute_all_subsequence_positions(GeneratorWords, PhraseWords, AllPositions) :-
	compute_all_subsequence_positions_1(GeneratorWords, PhraseWords, AllPositions0),
	% If AllPositions0 is [], there was no match, which should mean that
	% GeneratorWords contains one of more components of a split word such as "breastfeeding".
	% E.g., if GeneratorWords is [breast] or [feeding] or [breast,feeding],
	% and PhraseWords is [... breastfeeding, ... ], then AllPositions0 could be [],
	% so we need to expand PhraseWords using the split-word table.
	% This expansion transforms [... breastfeeding, ... ] into [ ... breast,feeding, ... ].
	( AllPositions0 == [],
	  member(SplitWord, PhraseWords),
	  split_word(SplitWord, _Word1, _Word2) ->
	  expand_split_word_list(PhraseWords, ExpandedPhraseWords),
	  compute_all_subsequence_positions_1(GeneratorWords, ExpandedPhraseWords, AllPositions1),
	  decrease_end_pos(AllPositions1, AllPositions2),
	  ( AllPositions2 == [] ->
	    format('~NERROR: compute_all_subsequence_positions/3 failed for ~p and ~p~n',
		   [GeneratorWords,PhraseWords])
	  ; AllPositions = AllPositions2
	  )
	; AllPositions = AllPositions0
	).

% In the following comments, casp == compute_all_subsequence_positions.
% If we call, e.g., casp([breast,feeding], [breastfeeding,patients], Pos),
% Pos will be [], so we expand [breastfeeding,patients] to [breast,feeding,patients],
% and call casp([breast,feeding], [breast,feeding,patients], Pos).
% That call to casp will instantiate Pos to [[1,2]];
% however, it should really be [[1,1]], so we have to decrease the end positions by 1.

decrease_end_pos(AllPositionsIn, AllPositionsOut) :-
	(  foreach([StartPos,OrigEndPos], AllPositionsIn),
	   foreach([StartPos,NewEndPos], AllPositionsOut)
	do NewEndPos is OrigEndPos - 1
	).

% The following is a more elegant way of doing compute_all_subsequence_position/3,
% which after extensive testing, has also proved to be faster, and it doesn't use findall/3!

% Given two lists, HeadWords and AllWords,
% we want to know all subsequence positions in AllWords in which HeadWords appear.
% E.g., if HeadWords is [a,b] and AllWords is [a,b,c,a,b,c,a,b,c],
%                                              1 2 3 4 5 6 7 8 9
% [a,b] appears in positions [1,2], [4,5], and [7,8], so
% AllPositions would be [[1,2], [4,5], [7,8]]

% A more real-world example:
% If HeadWords is [patients] and AllWords is [breastfeeding,patients],
% then AllPositions would be [[2,2]].
compute_all_subsequence_positions_1([], _Words, [[0,-1]]).
compute_all_subsequence_positions_1([FirstGeneratorWord|RestGeneratorWords], Words, AllPositions) :-
	% reversed order of args from QP library version!
	last([FirstGeneratorWord|RestGeneratorWords], LastGeneratorWord),
	all_positions(Words, FirstGeneratorWord, 1, FirstPositions),
	all_positions(Words, LastGeneratorWord,  1, LastPositions),
 	length([FirstGeneratorWord|RestGeneratorWords], GeneratorWordListLength),
	all_pairs(FirstPositions, LastPositions, GeneratorWordListLength, AllPositions, []).

% Given a list L and an element X, generate all index positions of X in L.
% E.g., calling
% all_positions([a,b,c,a,b,c,a,b,c], a, 1, AllPositions)
% Positions:     1 2 3 4 5 6 7 8 9
% instantiates AllPositions to [1,4,7]

all_positions([], _GeneratorWord, _Index, []).
all_positions([H|T], GeneratorWord, Index, AllPositions) :-
	( H == GeneratorWord ->
	  AllPositions = [Index|Rest]
	; AllPositions = Rest
	),
	NextIndex is Index + 1,
	all_positions(T, GeneratorWord, NextIndex, Rest).

% Given two lists L1 and L2, generate all pairs X1-X2
% (each pair is currently represented as a 2-element list, which is not good!)
% such that
% * X1 is a member of L1,
% * X2 is a member of L2,
% * X1 =< X2, and
% * (X2 - X1) + 1 == GeneratorWordListLength
% E.g., calling
% all_pairs([1,3,5], [2,4,6], GeneratorWordListLength, AllPairs, [])
% instantiates AllPairs to [[1,2],[1,4],[1,6],[3,4],[3,6],[5,6]],
% but the constraint (X2 - X1) + 1 == GeneratorWordListLength would remove some of those pairs.

all_pairs([], _List2, _DesiredLength, AllPairs, AllPairs).
all_pairs([H|T], List2, DesiredLength, AllPairs, Tail) :-
	all_pairs_1(List2, H, DesiredLength, AllPairs, Rest),
	all_pairs(T, List2, DesiredLength, Rest, Tail).

all_pairs_1([], _X, _DesiredLength, Tail, Tail).
all_pairs_1([H|T], X, DesiredLength, AllPairs, Tail) :-
	( X =< H,
	  (H - X) + 1 =:= DesiredLength ->
	  AllPairs = [[X,H]|RestAllPairs]
	; RestAllPairs = AllPairs
	),
	all_pairs_1(T, X, DesiredLength, RestAllPairs, Tail).

% Old version:
% csp(SubWords, Words, Res) :-
% 	% compute_all_subsequence_positions(SubWords, Words, Res).
% 	compute_all_positions(SubWords, Words, Res).

% compute_all_subsequence_positions(SubWords, Words, Positions) :-
% 	( findall(Position,
% 		  compute_one_subsequence_position(SubWords,Words,Position),
% 		  Positions),f
% 	  Positions \== [] ->
% 	  true
% 	; format('~NERROR: compute_all_subsequence_positions/3 failed for ~p and ~p~n',
% 		 [SubWords,Words])
% 	).
%
% compute_one_subsequence_position([], _Words, [0,-1]).
% compute_one_subsequence_position([SubWord|RestSubWords], Words, Position) :-
% 	SubWords = [SubWord|RestSubWords],
% 	% X is an initial subset of Words
% 	% append(X, _Suffix, Words),
% 	% append(Prefix, SubWords, X),
% 	append([Prefix,SubWords,_Suffix], Words),
% 	length(Prefix, PrefixLength),
% 	length(SubWords, SubWordsLength),
% 	BeginPos is PrefixLength + 1,
% 	EndPos is BeginPos + SubWordsLength - 1,
% 	Position = [BeginPos,EndPos].

/* compute_head_involvement(+GeneratorPosition, +HeadPosition,
                            -GeneratorInvolvesHead)

compute_head_involvement/3
xxx
*/

compute_head_involvement(GeneratorPosition, HeadPosition, GeneratorInvolvesHead) :-
	( positions_overlap(GeneratorPosition,HeadPosition) ->
	  GeneratorInvolvesHead = yes
	; GeneratorInvolvesHead = no
	).

/* write_all_variants(+GVCs)

write_all_variants/1 writes the variants (Vs) in GVCs. */

write_all_variants([]).
write_all_variants([gvc(G,Vs,_Cs)|Rest]) :-
	G = v(Generator,Categories,_,_,_,_),
	with_output_to_codes(format('~p', [Categories]), StringCats),
	concatenate_items_to_atom([Generator," ",StringCats], GeneratorLabel),
	dump_variants_labelled(GeneratorLabel, Vs),
	format('~n', []),
	write_all_variants(Rest).

/* aao(?AA)

aao/1 defines those lexical inflections which are ONLY AAs.  (2006 version)  */

%% version for checking
%aao(AA) :-
%    aaox(AA),
%    !,
%    format('aao call:|~p|~n',[AA]).
%
%:- ensure_loaded('aaox.pl').

% normal version

/* vdx(?Word, ?Variant)

vdx/2 defines exceptions to the results produced by the
derivational morphology module.
This predicate should be temporary since the exceptions should be built
into the module.
See metamap/tools/mm_variants/data.06/ for the study which produced this
predicate.
(2006 edition).
*/

%% version for checking
%vdx(Word,Variant) :-
%    vdxx(Word,Variant),
%    !,
%    format('vdx call:|~p|~p|~n',[Word,Variant]).
%
%:- ensure_loaded('vdxx.pl').

% Normal version


