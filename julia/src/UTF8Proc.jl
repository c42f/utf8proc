#
# Copyright (c) 2014-2021 Steven G. Johnson, Jiahao Chen, Peter Colberg, Tony Kelman, Scott P. Jones, Claire Foster and other contributors.
# Copyright (c) 2009 Public Software Group e. V., Berlin, Germany
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#

module UTF8Proc

# Option flags used by several functions in the library.
# The given UTF-8 input is NULL terminated.
const NULLTERM  = (1<<0)
# Unicode Versioning Stability has to be respected.
const STABLE    = (1<<1)
# Compatibility decomposition (i.e. formatting information is lost).
const COMPAT    = (1<<2)
# Return a result with decomposed characters.
const COMPOSE   = (1<<3)
# Return a result with decomposed characters.
const DECOMPOSE = (1<<4)
# Strip "default ignorable characters" such as SOFT-HYPHEN or ZERO-WIDTH-SPACE.
const IGNORE    = (1<<5)
# Return an error, if the input contains unassigned codepoints.
const REJECTNA  = (1<<6)
#
# Indicating that NLF-sequences (LF, CRLF, CR, NEL) are representing a
# line break, and should be converted to the codepoint for line
# separation (LS).
#
const NLF2LS    = (1<<7)
#
# Indicating that NLF-sequences are representing a paragraph break, and
# should be converted to the codepoint for paragraph separation
# (PS).
#
const NLF2PS    = (1<<8)
# Indicating that the meaning of NLF-sequences is unknown.
const NLF2LF    = (NLF2LS | NLF2PS)
# Strips and/or convers control characters.
#
# NLF-sequences are transformed into space, except if one of the
# NLF2LS/PS/LF options is given. HorizontalTab (HT) and FormFeed (FF)
# are treated as a NLF-sequence in this case.  All other control
# characters are simply removed.
#
const STRIPCC   = (1<<9)
#
# Performs unicode case folding, to be able to do a case-insensitive
# string comparison.
#
const CASEFOLD  = (1<<10)
#
# Inserts 0xFF bytes at the beginning of each sequence which is
# representing a single grapheme cluster (see UAX#29).
#
const CHARBOUND = (1<<11)
# Lumps certain characters together.
#
# E.g. HYPHEN U+2010 and MINUS U+2212 to ASCII "-". See lump.md for details.
#
# If NLF2LF is set, this includes a transformation of paragraph and
# line separators to ASCII line-feed (LF).
#
const LUMP      = (1<<12)
# Strips all character markings.
#
# This includes non-spacing, spacing and enclosing (i.e. accents).
# @note This option works only with @ref COMPOSE or
#       @ref DECOMPOSE
#
const STRIPMARK = (1<<13)
#
# Strip unassigned codepoints.
#
const STRIPNA    = (1<<14)

# Error codes being returned by almost all functions.
#
# Memory could not be allocated.
const ERROR_NOMEM = -1
# The given string is too long to be processed.
const ERROR_OVERFLOW = -2
# The given string is not a legal UTF-8 string.
const ERROR_INVALIDUTF8 = -3
# The @ref REJECTNA flag was set and an unassigned codepoint was found.
const ERROR_NOTASSIGNED = -4
# Invalid options have been used.
const ERROR_INVALIDOPTS = -5

# @name Types

# Holds the value of a property.
# C: utf8proc_propval_t
const PropVal = Int16

# Struct containing information about a codepoint.
struct CharProperty
    category::PropVal 
    combining_class::PropVal 
    bidi_class::PropVal 
    decomp_type::PropVal 
    decomp_seqindex::UInt16 
    casefold_seqindex::UInt16 
    uppercase_seqindex::UInt16 
    lowercase_seqindex::UInt16 
    titlecase_seqindex::UInt16 
    comb_index::UInt16 
    flags::UInt16 
    # unsigned bidi_mirrored:1
    # unsigned comp_exclusion:1
    # #
    #  # Can this codepoint be ignored?
    #  #
    #  # Used by utf8proc_decompose_char() when @ref IGNORE is
    #  # passed as an option.
    #  #
    # unsigned ignorable:1
    # unsigned control_boundary:1
    # # The width of the codepoint.
    # unsigned charwidth:2
    # unsigned pad:2
    # #
    #  # Boundclass.
    #  # @see utf8proc_boundclass_t.
    #  #
    # unsigned boundclass:6
    # unsigned indic_conjunct_break:2
end

function CharProperty(category, combining_class, bidi_class, decomp_type,
        decomp_seqindex, casefold_seqindex, uppercase_seqindex, lowercase_seqindex,
        titlecase_seqindex, comb_index, bidi_mirrored, comp_exclusion, ignorable,
        control_boundary, charwidth, boundclass, indic_conjunct_break)
    flags = pack_flags(bidi_mirrored, comp_exclusion, ignorable, control_boundary,
                       charwidth, boundclass, indic_conjunct_break)
    CharProperty(category, combining_class, bidi_class, decomp_type,
                 decomp_seqindex, casefold_seqindex, uppercase_seqindex,
                 lowercase_seqindex, titlecase_seqindex, comb_index, flags)
end

function pack_flags(bidi_mirrored, comp_exclusion, ignorable, control_boundary,
                    charwidth, boundclass, indic_conjunct_break)
    flags = UInt16(0)
    bit_offset = 0
    function pack_flag(f, width)
        mask = (1 << width)-1
        f & mask == f || error("Flag out of range")
        flags |= (f & mask) << bit_offset
        bit_offset += width
    end
    pack_flag(bidi_mirrored, 1)
    pack_flag(comp_exclusion, 1)
    pack_flag(ignorable, 1)
    pack_flag(control_boundary, 1)
    pack_flag(charwidth, 2)
    pack_flag(0, 2)
    pack_flag(boundclass, 6)
    pack_flag(indic_conjunct_break, 2)
    flags
end

function Base.getproperty(cp::CharProperty, name::Symbol)
    name === :category             ? getfield(cp, :category)           :
    name === :combining_class      ? getfield(cp, :combining_class)    :
    name === :bidi_class           ? getfield(cp, :bidi_class)         :
    name === :decomp_type          ? getfield(cp, :decomp_type)        :
    name === :decomp_seqindex      ? getfield(cp, :decomp_seqindex)    :
    name === :casefold_seqindex    ? getfield(cp, :casefold_seqindex)  :
    name === :uppercase_seqindex   ? getfield(cp, :uppercase_seqindex) :
    name === :lowercase_seqindex   ? getfield(cp, :lowercase_seqindex) :
    name === :titlecase_seqindex   ? getfield(cp, :titlecase_seqindex) :
    name === :comb_index           ? getfield(cp, :comb_index)         :
    begin
        f = getfield(cp, :flags)
        name === :bidi_mirrored        ? (f & 0x01 == 0x00)            :
        name === :comp_exclusion       ? ((f >> 1)  & 0x01 == 0x00)    :
        name === :ignorable            ? ((f >> 2)  & 0x01 == 0x00)    :
        name === :control_boundary     ? ((f >> 3)  & 0x01 == 0x00)    :
        name === :charwidth            ? ((f >> 4)  & 0x03        )    :
        # name === :pad                  ? ((f >> 1) & 0x03        )   :
        name === :boundclass           ? ((f >> 8)  & 0x3f        )    :
        name === :indic_conjunct_break ? ((f >> 14) & 0x03        )    :
        error("No field")
    end
end

# Unicode categories.
const CATEGORY_CN  = 0 # Other, not assigned
const CATEGORY_LU  = 1 # Letter, uppercase
const CATEGORY_LL  = 2 # Letter, lowercase
const CATEGORY_LT  = 3 # Letter, titlecase
const CATEGORY_LM  = 4 # Letter, modifier
const CATEGORY_LO  = 5 # Letter, other
const CATEGORY_MN  = 6 # Mark, nonspacing
const CATEGORY_MC  = 7 # Mark, spacing combining
const CATEGORY_ME  = 8 # Mark, enclosing
const CATEGORY_ND  = 9 # Number, decimal digit
const CATEGORY_NL = 10 # Number, letter
const CATEGORY_NO = 11 # Number, other
const CATEGORY_PC = 12 # Punctuation, connector
const CATEGORY_PD = 13 # Punctuation, dash
const CATEGORY_PS = 14 # Punctuation, open
const CATEGORY_PE = 15 # Punctuation, close
const CATEGORY_PI = 16 # Punctuation, initial quote
const CATEGORY_PF = 17 # Punctuation, final quote
const CATEGORY_PO = 18 # Punctuation, other
const CATEGORY_SM = 19 # Symbol, math
const CATEGORY_SC = 20 # Symbol, currency
const CATEGORY_SK = 21 # Symbol, modifier
const CATEGORY_SO = 22 # Symbol, other
const CATEGORY_ZS = 23 # Separator, space
const CATEGORY_ZL = 24 # Separator, line
const CATEGORY_ZP = 25 # Separator, paragraph
const CATEGORY_CC = 26 # Other, control
const CATEGORY_CF = 27 # Other, format
const CATEGORY_CS = 28 # Other, surrogate
const CATEGORY_CO = 29 # Other, private use

# Bidirectional character classes.
# utf8proc_bidi_class_t
const BIDI_CLASS_L     = 1 # Left-to-Right
const BIDI_CLASS_LRE   = 2 # Left-to-Right Embedding
const BIDI_CLASS_LRO   = 3 # Left-to-Right Override
const BIDI_CLASS_R     = 4 # Right-to-Left
const BIDI_CLASS_AL    = 5 # Right-to-Left Arabic
const BIDI_CLASS_RLE   = 6 # Right-to-Left Embedding
const BIDI_CLASS_RLO   = 7 # Right-to-Left Override
const BIDI_CLASS_PDF   = 8 # Pop Directional Format
const BIDI_CLASS_EN    = 9 # European Number
const BIDI_CLASS_ES   = 10 # European Separator
const BIDI_CLASS_ET   = 11 # European Number Terminator
const BIDI_CLASS_AN   = 12 # Arabic Number
const BIDI_CLASS_CS   = 13 # Common Number Separator
const BIDI_CLASS_NSM  = 14 # Nonspacing Mark
const BIDI_CLASS_BN   = 15 # Boundary Neutral
const BIDI_CLASS_B    = 16 # Paragraph Separator
const BIDI_CLASS_S    = 17 # Segment Separator
const BIDI_CLASS_WS   = 18 # Whitespace
const BIDI_CLASS_ON   = 19 # Other Neutrals
const BIDI_CLASS_LRI  = 20 # Left-to-Right Isolate
const BIDI_CLASS_RLI  = 21 # Right-to-Left Isolate
const BIDI_CLASS_FSI  = 22 # First Strong Isolate
const BIDI_CLASS_PDI  = 23 # Pop Directional Isolate

# Decomposition type.
# utf8proc_decomp_type_t
const DECOMP_TYPE_FONT      = 1 # Font
const DECOMP_TYPE_NOBREAK   = 2 # Nobreak
const DECOMP_TYPE_INITIAL   = 3 # Initial
const DECOMP_TYPE_MEDIAL    = 4 # Medial
const DECOMP_TYPE_FINAL     = 5 # Final
const DECOMP_TYPE_ISOLATED  = 6 # Isolated
const DECOMP_TYPE_CIRCLE    = 7 # Circle
const DECOMP_TYPE_SUPER     = 8 # Super
const DECOMP_TYPE_SUB       = 9 # Sub
const DECOMP_TYPE_VERTICAL = 10 # Vertical
const DECOMP_TYPE_WIDE     = 11 # Wide
const DECOMP_TYPE_NARROW   = 12 # Narrow
const DECOMP_TYPE_SMALL    = 13 # Small
const DECOMP_TYPE_SQUARE   = 14 # Square
const DECOMP_TYPE_FRACTION = 15 # Fraction
const DECOMP_TYPE_COMPAT   = 16 # Compat

# Boundclass property. (TR29)
# utf8proc_boundclass_t
const BOUNDCLASS_START              =  0 # Start
const BOUNDCLASS_OTHER              =  1 # Other
const BOUNDCLASS_CR                 =  2 # Cr
const BOUNDCLASS_LF                 =  3 # Lf
const BOUNDCLASS_CONTROL            =  4 # Control
const BOUNDCLASS_EXTEND             =  5 # Extend
const BOUNDCLASS_L                  =  6 # L
const BOUNDCLASS_V                  =  7 # V
const BOUNDCLASS_T                  =  8 # T
const BOUNDCLASS_LV                 =  9 # Lv
const BOUNDCLASS_LVT                = 10 # Lvt
const BOUNDCLASS_REGIONAL_INDICATOR = 11 # Regional indicator
const BOUNDCLASS_SPACINGMARK        = 12 # Spacingmark
const BOUNDCLASS_PREPEND            = 13 # Prepend
const BOUNDCLASS_ZWJ                = 14 # Zero Width Joiner
# the following are no longer used in Unicode 11, but we keep
# the constants here for backward compatibility
const BOUNDCLASS_E_BASE             = 15 # Emoji Base
const BOUNDCLASS_E_MODIFIER         = 16 # Emoji Modifier
const BOUNDCLASS_GLUE_AFTER_ZWJ     = 17 # Glue_After_ZWJ
const BOUNDCLASS_E_BASE_GAZ         = 18 # E_BASE + GLUE_AFTER_ZJW
# the Extended_Pictographic property is used in the Unicode 11
# grapheme-boundary rules, so we store it in the boundclass field
const BOUNDCLASS_EXTENDED_PICTOGRAPHIC = 19
const BOUNDCLASS_E_ZWG = 20 # BOUNDCLASS_EXTENDED_PICTOGRAPHIC + ZWJ


# Indic_Conjunct_Break property. (TR44)
# utf8proc_indic_conjunct_break_t
const INDIC_CONJUNCT_BREAK_NONE = 0
const INDIC_CONJUNCT_BREAK_LINKER = 1
const INDIC_CONJUNCT_BREAK_CONSONANT = 2
const INDIC_CONJUNCT_BREAK_EXTEND = 3

# The utf8proc supported Unicode version as a string MAJOR.MINOR.PATCH.
const unicode_version = v"15.1.0"

# Returns an informative error string for the given utf8proc error code
# (e.g. the error codes returned by utf8proc_map()).
# const char *utf8proc_errmsg(utf8proc_ssize_t errcode)

#
# Reads a single codepoint from the UTF-8 sequence being pointed to by `str`.
# The maximum number of bytes read is `strlen`, unless `strlen` is
# negative (in which case up to 4 bytes are read).
#
# If a valid codepoint could be read, it is stored in the variable
# pointed to by `codepoint_ref`, otherwise that variable will be set to -1.
# In case of success, the number of bytes read is returned; otherwise, a
# negative error code is returned.
#
# utf8proc_ssize_t utf8proc_iterate(const utf8proc_uint8_t *str, utf8proc_ssize_t strlen, utf8proc_int32_t *codepoint_ref)
# See nextind()?

#
# Check if a codepoint is valid (regardless of whether it has been
# assigned a value by the current Unicode standard).
#
# @return 1 if the given `codepoint` is valid and otherwise return 0.
#
#utf8proc_bool utf8proc_codepoint_valid(utf8proc_int32_t codepoint)

#
# Encodes the codepoint as an UTF-8 string in the byte array pointed
# to by `dst`. This array must be at least 4 bytes long.
#
# In case of success the number of bytes written is returned, and
# otherwise 0 is returned.
#
# This function does not check whether `codepoint` is valid Unicode.
#
#utf8proc_ssize_t utf8proc_encode_char(utf8proc_int32_t codepoint, utf8proc_uint8_t *dst)

function unsafe_get_property(uc)
  # ASSERT: uc >= 0 && uc < 0x110000
  # TODO: @inbounds?
  return @inbounds _properties[_stage2table[_stage1table[uc >> 8 + 1] + uc & 0xFF + 1] + 1]
end

#
# Look up the properties for a given codepoint.
#
# @param codepoint The Unicode codepoint.
#
# @returns
# A pointer to a (constant) struct containing information about
# the codepoint.
# @par
# If the codepoint is unassigned or invalid, a pointer to a special struct is
# returned in which `category` is 0 (@ref CATEGORY_CN).
#
function utf8proc_get_property(uc)
    return uc < 0 || uc >= 0x110000 ? _properties[1] : unsafe_get_property(uc);
end

# Decompose a codepoint into an array of codepoints.
 #
 # @param codepoint the codepoint.
 # @param dst the destination buffer.
 # @param bufsize the size of the destination buffer.
 # @param options one or more of the following flags:
 # - @ref REJECTNA  - return an error `codepoint` is unassigned
 # - @ref IGNORE    - strip "default ignorable" codepoints
 # - @ref CASEFOLD  - apply Unicode casefolding
 # - @ref COMPAT    - replace certain codepoints with their
 #                             compatibility decomposition
 # - @ref CHARBOUND - insert 0xFF bytes before each grapheme cluster
 # - @ref LUMP      - lump certain different codepoints together
 # - @ref STRIPMARK - remove all character marks
 # - @ref STRIPNA   - remove unassigned codepoints
 # @param last_boundclass
 # Pointer to an integer variable containing
 # the previous codepoint's (boundclass + indic_conjunct_break << 1) if the @ref CHARBOUND
 # option is used.  If the string is being processed in order, this can be initialized to 0 for
 # the beginning of the string, and is thereafter updated automatically.  Otherwise, this parameter is ignored.
 #
 # @return
 # In case of success, the number of codepoints written is returned; in case
 # of an error, a negative error code is returned (utf8proc_errmsg()).
 # @par
 # If the number of written codepoints would be bigger than `bufsize`, the
 # required buffer size is returned, while the buffer will be overwritten with
 # undefined data.
 #
# utf8proc_ssize_t utf8proc_decompose_char(
#   utf8proc_int32_t codepoint, utf8proc_int32_t *dst, utf8proc_ssize_t bufsize,
#   utf8proc_option_t options, int *last_boundclass
# )
# ^TODO

#
 # The same as utf8proc_decompose_char(), but acts on a whole UTF-8
 # string and orders the decomposed sequences correctly.
 #
 # If the @ref NULLTERM flag in `options` is set, processing
 # will be stopped, when a NULL byte is encountered, otherwise `strlen`
 # bytes are processed.  The result (in the form of 32-bit unicode
 # codepoints) is written into the buffer being pointed to by
 # `buffer` (which must contain at least `bufsize` entries).  In case of
 # success, the number of codepoints written is returned; in case of an
 # error, a negative error code is returned (utf8proc_errmsg()).
 # See utf8proc_decompose_custom() to supply additional transformations.
 #
 # If the number of written codepoints would be bigger than `bufsize`, the
 # required buffer size is returned, while the buffer will be overwritten with
 # undefined data.
 #
# utf8proc_ssize_t utf8proc_decompose(
#   const utf8proc_uint8_t *str, utf8proc_ssize_t strlen,
#   utf8proc_int32_t *buffer, utf8proc_ssize_t bufsize, utf8proc_option_t options
# )
# ^ TODO

#
 # The same as utf8proc_decompose(), but also takes a `custom_func` mapping function
 # that is called on each codepoint in `str` before any other transformations
 # (along with a `custom_data` pointer that is passed through to `custom_func`).
 # The `custom_func` argument is ignored if it is `NULL`.  See also utf8proc_map_custom().
 #
# utf8proc_ssize_t utf8proc_decompose_custom(
#   const utf8proc_uint8_t *str, utf8proc_ssize_t strlen,
#   utf8proc_int32_t *buffer, utf8proc_ssize_t bufsize, utf8proc_option_t options,
#   utf8proc_custom_func custom_func, void *custom_data
#)
# ^ TODO

#
 # Normalizes the sequence of `length` codepoints pointed to by `buffer`
 # in-place (i.e., the result is also stored in `buffer`).
 #
 # @param buffer the (native-endian UTF-32) unicode codepoints to re-encode.
 # @param length the length (in codepoints) of the buffer.
 # @param options a bitwise or (`|`) of one or more of the following flags:
 # - @ref NLF2LS  - convert LF, CRLF, CR and NEL into LS
 # - @ref NLF2PS  - convert LF, CRLF, CR and NEL into PS
 # - @ref NLF2LF  - convert LF, CRLF, CR and NEL into LF
 # - @ref STRIPCC - strip or convert all non-affected control characters
 # - @ref COMPOSE - try to combine decomposed codepoints into composite
 #                           codepoints
 # - @ref STABLE  - prohibit combining characters that would violate
 #                           the unicode versioning stability
 #
 # @return
 # In case of success, the length (in codepoints) of the normalized UTF-32 string is
 # returned; otherwise, a negative error code is returned (utf8proc_errmsg()).
 #
 # @warning The entries of the array pointed to by `str` have to be in the
 #          range `0x0000` to `0x10FFFF`. Otherwise, the program might crash!
 #
# utf8proc_ssize_t utf8proc_normalize_utf32(utf8proc_int32_t *buffer, utf8proc_ssize_t length, utf8proc_option_t options)

#
 # Reencodes the sequence of `length` codepoints pointed to by `buffer`
 # UTF-8 data in-place (i.e., the result is also stored in `buffer`).
 # Can optionally normalize the UTF-32 sequence prior to UTF-8 conversion.
 #
 # @param buffer the (native-endian UTF-32) unicode codepoints to re-encode.
 # @param length the length (in codepoints) of the buffer.
 # @param options a bitwise or (`|`) of one or more of the following flags:
 # - @ref NLF2LS  - convert LF, CRLF, CR and NEL into LS
 # - @ref NLF2PS  - convert LF, CRLF, CR and NEL into PS
 # - @ref NLF2LF  - convert LF, CRLF, CR and NEL into LF
 # - @ref STRIPCC - strip or convert all non-affected control characters
 # - @ref COMPOSE - try to combine decomposed codepoints into composite
 #                           codepoints
 # - @ref STABLE  - prohibit combining characters that would violate
 #                           the unicode versioning stability
 # - @ref CHARBOUND - insert 0xFF bytes before each grapheme cluster
 #
 # @return
 # In case of success, the length (in bytes) of the resulting nul-terminated
 # UTF-8 string is returned; otherwise, a negative error code is returned
 # (utf8proc_errmsg()).
 #
 # @warning The amount of free space pointed to by `buffer` must
 #          exceed the amount of the input data by one byte, and the
 #          entries of the array pointed to by `str` have to be in the
 #          range `0x0000` to `0x10FFFF`. Otherwise, the program might crash!
 #
#utf8proc_ssize_t utf8proc_reencode(utf8proc_int32_t *buffer, utf8proc_ssize_t length, utf8proc_option_t options)
# ^ TODO

#
 # Given a pair of consecutive codepoints, return whether a grapheme break is
 # permitted between them (as defined by the extended grapheme clusters in UAX#29).
 #
 # @param codepoint1 The first codepoint.
 # @param codepoint2 The second codepoint, occurring consecutively after `codepoint1`.
 # @param state Beginning with Version 29 (Unicode 9.0.0), this algorithm requires
 #              state to break graphemes. This state can be passed in as a pointer
 #              in the `state` argument and should initially be set to 0. If the
 #              state is not passed in (i.e. a null pointer is passed), UAX#29 rules
 #              GB10/12/13 which require this state will not be applied, essentially
 #              matching the rules in Unicode 8.0.0.
 #
 # @warning If the state parameter is used, `utf8proc_grapheme_break_stateful` must
 #          be called IN ORDER on ALL potential breaks in a string.  However, it
 #          is safe to reset the state to zero after a grapheme break.
 #
#utf8proc_bool utf8proc_grapheme_break_stateful(
#    utf8proc_int32_t codepoint1, utf8proc_int32_t codepoint2, utf8proc_int32_t *state)
# ^ TODO

#
 # Same as utf8proc_grapheme_break_stateful(), except without support for the
 # Unicode 9 additions to the algorithm. Supported for legacy reasons.
 #
#utf8proc_bool utf8proc_grapheme_break(
#    utf8proc_int32_t codepoint1, utf8proc_int32_t codepoint2)
# ^ TODO


#
 # Given a codepoint `c`, return the codepoint of the corresponding
 # lower-case character, if any; otherwise (if there is no lower-case
 # variant, or if `c` is not a valid codepoint) return `c`.
 #
# utf8proc_int32_t utf8proc_tolower(utf8proc_int32_t c)
# ^ TODO

#
 # Given a codepoint `c`, return the codepoint of the corresponding
 # upper-case character, if any; otherwise (if there is no upper-case
 # variant, or if `c` is not a valid codepoint) return `c`.
 #
# utf8proc_int32_t utf8proc_toupper(utf8proc_int32_t c)
# ^ TODO

#
 # Given a codepoint `c`, return the codepoint of the corresponding
 # title-case character, if any; otherwise (if there is no title-case
 # variant, or if `c` is not a valid codepoint) return `c`.
 #
#utf8proc_int32_t utf8proc_totitle(utf8proc_int32_t c)
# ^ TODO

#
 # Given a codepoint `c`, return `1` if the codepoint corresponds to a lower-case character
 # and `0` otherwise.
 #
#int utf8proc_islower(utf8proc_int32_t c)
# ^ TODO

#
 # Given a codepoint `c`, return `1` if the codepoint corresponds to an upper-case character
 # and `0` otherwise.
 #
#int utf8proc_isupper(utf8proc_int32_t c)
# ^ TODO

#
 # Given a codepoint, return a character width analogous to `wcwidth(codepoint)`,
 # except that a width of 0 is returned for non-printable codepoints
 # instead of -1 as in `wcwidth`.
 #
 # @note
 # If you want to check for particular types of non-printable characters,
 # (analogous to `isprint` or `iscntrl`), use utf8proc_category().
#int utf8proc_charwidth(utf8proc_int32_t codepoint)
# ^ TODO

#
 # Return the Unicode category for the codepoint (one of the
 # @ref utf8proc_category_t constants.)
 #
#utf8proc_category_t utf8proc_category(utf8proc_int32_t codepoint)
# ^TODO

#
 # Return the two-letter (nul-terminated) Unicode category string for
 # the codepoint (e.g. `"Lu"` or `"Co"`).
 #
#const char *utf8proc_category_string(utf8proc_int32_t codepoint)
# ^TODO

#
 # Maps the given UTF-8 string pointed to by `str` to a new UTF-8
 # string, allocated dynamically by `malloc` and returned via `dstptr`.
 #
 # If the @ref NULLTERM flag in the `options` field is set,
 # the length is determined by a NULL terminator, otherwise the
 # parameter `strlen` is evaluated to determine the string length, but
 # in any case the result will be NULL terminated (though it might
 # contain NULL characters with the string if `str` contained NULL
 # characters). Other flags in the `options` field are passed to the
 # functions defined above, and regarded as described.  See also
 # utf8proc_map_custom() to supply a custom codepoint transformation.
 #
 # In case of success the length of the new string is returned,
 # otherwise a negative error code is returned.
 #
 # @note The memory of the new UTF-8 string will have been allocated
 # with `malloc`, and should therefore be deallocated with `free`.
 #
#utf8proc_ssize_t utf8proc_map(
#  const utf8proc_uint8_t *str, utf8proc_ssize_t strlen, utf8proc_uint8_t **dstptr, utf8proc_option_t options
#)
# ^TODO

#
 # Like utf8proc_map(), but also takes a `custom_func` mapping function
 # that is called on each codepoint in `str` before any other transformations
 # (along with a `custom_data` pointer that is passed through to `custom_func`).
 # The `custom_func` argument is ignored if it is `NULL`.
 #
# utf8proc_ssize_t utf8proc_map_custom(
#   const utf8proc_uint8_t *str, utf8proc_ssize_t strlen, utf8proc_uint8_t **dstptr, utf8proc_option_t options,
#   utf8proc_custom_func custom_func, void *custom_data
# )

# @name Unicode normalization
 #
 # Returns a pointer to newly allocated memory of a NFD, NFC, NFKD, NFKC or
 # NFKC_Casefold normalized version of the null-terminated string `str`.  These
 # are shortcuts to calling utf8proc_map() with @ref NULLTERM
 # combined with @ref STABLE and flags indicating the normalization.
 #
# @{
# NFD normalization (@ref DECOMPOSE).
#utf8proc_uint8_t *utf8proc_NFD(const utf8proc_uint8_t *str)
# NFC normalization (@ref COMPOSE).
#utf8proc_uint8_t *utf8proc_NFC(const utf8proc_uint8_t *str)
# NFKD normalization (@ref DECOMPOSE and @ref COMPAT).
#utf8proc_uint8_t *utf8proc_NFKD(const utf8proc_uint8_t *str)
# NFKC normalization (@ref COMPOSE and @ref COMPAT).
#utf8proc_uint8_t *utf8proc_NFKC(const utf8proc_uint8_t *str)
#
 # NFKC_Casefold normalization (@ref COMPOSE and @ref COMPAT
 # and @ref CASEFOLD and @ref IGNORE).
 #
#utf8proc_uint8_t *utf8proc_NFKC_Casefold(const utf8proc_uint8_t *str)
# @}

include("data.jl")

end