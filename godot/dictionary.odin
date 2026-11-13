package godot

import gde "../gdextension"

// Dictionary reads answered from the engine's storage, with no call, once `check_dict_layout`
// proved it at load: the generated `size`, `is_empty`, `has`, `has_all` and `get` try these first
// (tools/odin_bindgen.py IN_PLACE) and make the engine call only when they return false. Each answers
// as Dictionary does in Godot 4.7-stable (core/variant/dictionary.cpp): a key is found by the
// engine's own HashMap probe, under the hash Variant::recursive_hash gives it, and compares with
// StringLikeVariantComparator as Array's search does (array.odin). The in-place lookup handles a key
// that is nil, a bool, an int, a float, a String, a StringName or a RID; a key of any other type, or
// one a typed Dictionary would convert or reject, goes to the engine.

// True when a Dictionary is the engine's DictionaryPrivate as `dict_map` reads it, and its
// StringNames keep their hash at `name_hash_offset`. `check_dict_layout` decides it at load; without
// it every read calls the engine.
@(private)
dict_layout_known: bool

// Where DictionaryPrivate keeps its HashMap: after its 32-bit reference count, padded to 8 bytes,
// and its read-only pointer.
@(private)
DICT_MAP_OFFSET :: 16

// Where DictionaryPrivate keeps the key type of a typed Dictionary, the first field of its first
// ContainerTypeValidate, after the HashMap. NIL when the keys are untyped.
@(private)
DICT_KEY_TYPE_OFFSET :: DICT_MAP_OFFSET + size_of(Dict_Map)

// Where DictionaryPrivate keeps the value type of a typed Dictionary, the first field of its second
// ContainerTypeValidate: past the first one's type (padded to 8 bytes), class name, script and
// `where` pointer. NIL when the values are untyped.
@(private)
DICT_VALUE_TYPE_OFFSET :: DICT_KEY_TYPE_OFFSET + 32

// The engine's HashMap<Variant, Variant> (core/templates/hash_map.h): a Robin Hood table of
// `hash_table_size_primes[capacity_idx]` slots, each an element pointer and its key's hash, 0 for
// an empty slot, with the elements also linked in insertion order.
@(private)
Dict_Map :: struct {
	elements:     [^]^Dict_Element,
	hashes:       [^]u32,
	head, tail:   ^Dict_Element,
	capacity_idx: u32,
	size:         u32,
}

// The engine's HashMapElement<Variant, Variant>.
@(private)
Dict_Element :: struct {
	next, prev: ^Dict_Element,
	key, value: Variant,
}

#assert(size_of(Dict_Map) == 40)
#assert(offset_of(Dict_Element, key) == 16)
#assert(size_of(Dictionary) == size_of(rawptr))

// The engine's hash_table_size_primes, the slot counts a HashMap grows through.
@(private)
DICT_PRIMES := [29]u32{
	5, 13, 23, 47, 97, 193, 389, 769, 1543, 3079, 6151, 12289, 24593, 49157, 98317, 196613, 393241,
	786433, 1572869, 3145739, 6291469, 12582917, 25165843, 50331653, 100663319, 201326611, 402653189,
	805306457, 1610612741,
}

// `2^64 / DICT_PRIMES[i]` rounded up, hash_table_size_primes_inv of core/templates/hashfuncs.h, for
// `dict_mod`.
@(private)
DICT_PRIMES_INV := [29]u64{
	3689348814741910324, 1418980313362273202, 802032351030850071, 392483916461905354,
	190172619316593316, 95578984837873325, 47420935922132524, 23987963684927896, 11955116055547344,
	5991147799191151, 2998982941588287, 1501077717772769, 750081082979285, 375261795343686,
	187625172388393, 93822606204624, 46909513691883, 23456218233098, 11728086747027, 5864041509391,
	2932024948977, 1466014921160, 733007198436, 366503839517, 183251896093, 91625960335, 45812983922,
	22906489714, 11453246088,
}

// `n % DICT_PRIMES[i]` with no division, as the engine's fastmod computes it: exact for any 32-bit
// `n` (Lemire, Kaser and Kurz, "Faster Remainder by Direct Computation").
@(private)
dict_mod :: #force_inline proc "contextless" (n: u32, i: u32) -> u32 {
	return u32((u128(DICT_PRIMES_INV[i] * u64(n)) * u128(DICT_PRIMES[i])) >> 64)
}

// Where a StringName's data keeps the hash of its name: after the reference count, the static count
// and the name, and in a build with DEBUG_ENABLED a reference counter too. `check_dict_layout` finds
// it at load. A StringName's data keeps its name String at byte 8.
@(private)
name_hash_offset: uintptr

@(private)
NAME_TEXT_OFFSET :: 8

// The HashMap of `d`. Only when `dict_layout_known`.
@(private)
dict_map :: #force_inline proc "contextless" (d: ^Dictionary) -> ^Dict_Map {
	return (^Dict_Map)(uintptr((^rawptr)(d)^) + DICT_MAP_OFFSET)
}

// The key type `d` is typed with, NIL when untyped. Only when `dict_layout_known`.
@(private)
dict_key_type :: #force_inline proc "contextless" (d: ^Dictionary) -> gde.VariantType {
	return gde.VariantType((^i32)(uintptr((^rawptr)(d)^) + DICT_KEY_TYPE_OFFSET)^)
}

// The value type `d` is typed with, NIL when untyped. Only when `dict_layout_known`.
@(private)
dict_value_type :: #force_inline proc "contextless" (d: ^Dictionary) -> gde.VariantType {
	return gde.VariantType((^i32)(uintptr((^rawptr)(d)^) + DICT_VALUE_TYPE_OFFSET)^)
}

// The entry count of `d`, read from its storage. Only when `dict_layout_known`; the generated `size`
// and `is_empty` use it then.
dict_stored_size :: #force_inline proc "contextless" (d: ^Dictionary) -> i64 {
	return i64(dict_map(d).size)
}

// hash_one_uint64 of core/templates/hashfuncs.h.
@(private)
hash_one_u64 :: #force_inline proc "contextless" (x: u64) -> u32 {
	v := ~x + (x << 18)
	v ~= v >> 31
	v *= 21
	v ~= v >> 11
	v += v << 6
	v ~= v >> 22
	return u32(v)
}

// hash_murmur3_one_32 of core/templates/hashfuncs.h.
@(private)
murmur3_one_32 :: #force_inline proc "contextless" (x, seed: u32) -> u32 {
	k := x * 0xcc9e2d51
	k = (k << 15) | (k >> 17)
	k *= 0x1b873593
	h := seed ~ k
	h = (h << 13) | (h >> 19)
	return h * 5 + 0xe6546b64
}

// hash_murmur3_one_double of core/templates/hashfuncs.cpp, from HASH_MURMUR3_SEED: -0 hashes as 0
// and every NaN as the quiet NaN.
@(private)
murmur3_one_double :: #force_inline proc "contextless" (x: f64) -> u32 {
	bits := transmute(u64)x
	if x == 0 { bits = 0 } else if x != x { bits = 0x7ff8000000000000 }
	return murmur3_one_32(u32(bits >> 32), murmur3_one_32(u32(bits), 0x7F07C65))
}

// String::hash of core/string/ustring.cpp: djb2 over the characters up to the first 0.
@(private)
string_djb2 :: #force_inline proc "contextless" (s: ^String) -> u32 {
	h := u32(5381)
	p := ([^]u32)((^rawptr)(s)^)
	if p == nil { return h }
	for i in 0 ..< string_stored_length(s) {
		if p[i] == 0 { break }
		h = h * 33 + p[i]
	}
	return h
}

// The hash the engine's HashMap files key `k` under: Variant::recursive_hash, with 0, which marks
// an empty slot, made 1. False for a key type whose hash the engine computes.
@(private)
dict_key_hash :: #force_inline proc "contextless" (k: ^Variant) -> (u32, bool) {
	at := rawptr(&k._opaque[8])
	h: u32
	#partial switch variant_tag(k) {
	case .NIL:         h = 0
	case .BOOL:        h = u32((^u8)(at)^ != 0)
	case .INT, .RID:   h = hash_one_u64((^u64)(at)^)
	case .FLOAT:       h = murmur3_one_double((^f64)(at)^)
	case .STRING:      h = string_djb2((^String)(at))
	case .STRING_NAME:
		h = name_stored_hash((^StringName)(at))
	case:
		return 0, false
	}
	return max(h, 1), true
}

// The hash StringName `n` keeps in its data: the engine's StringName::hash. The empty StringName,
// which has no data, hashes as the empty String does. Only when `dict_layout_known`.
@(private)
name_stored_hash :: #force_inline proc "contextless" (n: ^StringName) -> u32 {
	p := (^rawptr)(n)^
	return 5381 if p == nil else (^u32)(uintptr(p) + name_hash_offset)^
}

// The text of StringName `n`, borrowed, empty when `n` is.
@(private)
name_text :: #force_inline proc "contextless" (n: ^StringName) -> ^String {
	@(static) empty: String
	p := (^rawptr)(n)^
	return &empty if p == nil else (^String)(uintptr(p) + NAME_TEXT_OFFSET)
}

// Whether stored key `x` equals key `k` under StringLikeVariantComparator: hash_compare when both
// have the same type, a String and a StringName by text, and never otherwise.
@(private)
dict_key_same :: #force_inline proc "contextless" (x, k: ^Variant) -> bool {
	xt, kt := variant_tag(x), variant_tag(k)
	xa, ka := rawptr(&x._opaque[8]), rawptr(&k._opaque[8])
	if xt != kt {
		if xt == .STRING && kt == .STRING_NAME { return elem_eq((^String)(xa), name_text((^StringName)(ka))) }
		if xt == .STRING_NAME && kt == .STRING { return elem_eq(name_text((^StringName)(xa)), (^String)(ka)) }
		return false
	}
	#partial switch array_elem(kt) {
	case .NIL:    return true
	case .BOOL:   return array_value_same(u8, x, k)
	case .WORD:   return array_value_same(i64, x, k)
	case .DOUBLE: return array_value_same(f64, x, k)
	case .STRING: return array_value_same(String, x, k)
	case .NAME:   return array_value_same(rawptr, x, k)
	}
	return false
}

// The element of `d` whose key equals `k`, nil when none does, found by the engine's probe: from
// slot `hash % capacity` on, until an empty slot or one whose element sits nearer its own first
// slot than the probe has come. False when the engine answers: before `check_dict_layout` proved the
// layout, for a key of a type the probe does not hash, and for one a typed Dictionary would convert.
@(private)
dict_lookup :: #force_inline proc "contextless" (d: ^Dictionary, k: ^Variant) -> (^Dict_Element, bool) {
	if !dict_layout_known { return nil, false }
	typed := dict_key_type(d)
	if typed != .NIL && typed != variant_tag(k) { return nil, false }
	h, ok := dict_key_hash(k)
	if !ok { return nil, false }
	m := dict_map(d)
	if m.elements == nil || m.size == 0 { return nil, true }
	if m.capacity_idx >= len(DICT_PRIMES) { return nil, false }
	ci := m.capacity_idx
	capacity := DICT_PRIMES[ci]
	at := dict_mod(h, ci)
	for distance in 0 ..< capacity {
		held := m.hashes[at]
		if held == 0 { return nil, true }
		probe := at + capacity - dict_mod(held, ci)
		if probe >= capacity { probe -= capacity }
		if distance > probe { return nil, true }
		if held == h && dict_key_same(&m.elements[at].key, k) { return m.elements[at], true }
		at += 1
		if at == capacity { at = 0 }
	}
	return nil, true
}

// Dictionary.has in place: whether a key equals `key`. False when the engine answers.
dict_stored_has :: #force_inline proc "contextless" (d: ^Dictionary, key: Variant) -> (bool, bool) {
	key := variant_reload(key)
	e, ok := dict_lookup(d, (^Variant)(&key))
	return e != nil, ok
}

// Dictionary.has_all in place: whether every element of `keys` is a key of `d`, false at the first
// that is not. False when the engine answers, as it does when one of the keys before the first
// missing one is of a type the probe does not hash.
dict_stored_has_all :: proc "contextless" (d: ^Dictionary, keys: Array) -> (bool, bool) {
	if !array_layout_known { return false, false }
	keys := keys
	for &k in array_stored(&keys) {
		e, ok := dict_lookup(d, &k)
		if !ok { return false, false }
		if e == nil { return false, true }
	}
	return true, true
}

// Dictionary.get in place: a copy of the value `key` maps to, or of `default` when no key equals
// it. False when the engine answers.
dict_stored_get :: #force_inline proc "contextless" (d: ^Dictionary, key, default: Variant) -> (Variant, bool) {
	key := variant_reload(key)
	e, ok := dict_lookup(d, (^Variant)(&key))
	if !ok { return {}, false }
	if e != nil { return stored_copy(&e.value), true }
	default := variant_reload(default)
	return stored_copy((^Variant)(&default)), true
}

// The first element of `m`, in insertion order, whose value equals `v` under Variant::hash_compare,
// as Dictionary.find_key compares, both values comparing as `E`s; nil when none does.
@(private)
dict_value_scan :: proc "contextless" ($E: typeid, m: ^Dict_Map, v: ^Variant) -> ^Dict_Element {
	tag := variant_tag(v)
	e := m.head
	for _ in 0 ..< m.size {
		hit := variant_tag(&e.value) == tag
		when E != Array_Nil { hit = hit && array_value_same(E, &e.value, v) }
		if hit { return e }
		e = e.next
	}
	return nil
}

// Dictionary.find_key in place: a copy of the first key, in insertion order, whose value equals
// `value`, or a nil Variant when none does. False when the engine answers: before
// `check_dict_layout` proved the layout, for a value of a type the scan does not compare, and for
// one a typed Dictionary would convert.
dict_stored_find_key :: proc "contextless" (d: ^Dictionary, value: Variant) -> (Variant, bool) {
	if !dict_layout_known { return {}, false }
	value := variant_reload(value)
	v := (^Variant)(&value)
	typed := dict_value_type(d)
	if typed != .NIL && typed != variant_tag(v) { return {}, false }
	m := dict_map(d)
	e: ^Dict_Element
	switch array_elem(variant_tag(v)) {
	case .ENGINE: return {}, false
	case .NIL:    e = dict_value_scan(Array_Nil, m, v)
	case .BOOL:   e = dict_value_scan(u8, m, v)
	case .WORD:   e = dict_value_scan(i64, m, v)
	case .DOUBLE: e = dict_value_scan(f64, m, v)
	case .REAL_2: e = dict_value_scan([2]f32, m, v)
	case .REAL_3: e = dict_value_scan([3]f32, m, v)
	case .REAL_4: e = dict_value_scan([4]f32, m, v)
	case .INT_2:  e = dict_value_scan([2]i32, m, v)
	case .INT_3:  e = dict_value_scan([3]i32, m, v)
	case .INT_4:  e = dict_value_scan([4]i32, m, v)
	case .STRING: e = dict_value_scan(String, m, v)
	case .NAME:   e = dict_value_scan(rawptr, m, v)
	}
	if e == nil { return {}, true }
	return stored_copy(&e.key), true
}

// Dictionary.keys, or Dictionary.values for VALUES, in place: a new untyped Array of copies of the
// keys or values of `d` in insertion order, written into its storage. False when the engine
// answers: before `check_dict_layout` proved the layout, and when they are typed, as the engine
// types the Array then.
dict_stored_list :: proc "contextless" (d: ^Dictionary, $VALUES: bool) -> (Array, bool) {
	if !dict_layout_known { return {}, false }
	when VALUES {
		if dict_value_type(d) != .NIL { return {}, false }
	} else {
		if dict_key_type(d) != .NIL { return {}, false }
	}
	m := dict_map(d)
	out := array_new()
	if m.size == 0 { return out, true }
	// A new Array is its storage's only owner, so its NIL elements can be overwritten in place.
	array_resize(&out, i64(m.size))
	xs := array_stored(&out)
	if len(xs) != int(m.size) {
		destroy[.ARRAY](&out)
		return {}, false
	}
	e := m.head
	for &x in xs {
		x = stored_copy(&e.value) when VALUES else stored_copy(&e.key)
		e = e.next
	}
	return out, true
}

// Sets `dict_layout_known` from Dictionaries of known contents: one holding keys of every type the
// probe hashes, grown through several capacities, one emptied by erasing, and a typed one. Every key
// must be found where the engine's own lookup finds it, in the insertion order its key list gives.
check_dict_layout :: proc "contextless" () {
	dict_layout_known = false
	if !array_layout_known || !string_layout_known { return }
	name := name_of("check_dict_layout")
	defer destroy[.STRING_NAME](&name)
	name_text_ok := false
	data := (^rawptr)(&name)^
	engine_hash := u32(string_name_hash(&name))
	for off in ([2]uintptr{16, 20}) {
		if (^u32)(uintptr(data) + off)^ == engine_hash { name_hash_offset = off }
	}
	text := string_of("check_dict_layout")
	defer destroy[.STRING](&text)
	name_text_ok = name_hash_offset != 0 && elem_eq(name_text(&name), &text)

	d := dictionary_new()
	defer destroy[.DICTIONARY](&d)
	for k in 0 ..< 40 { dict_set(&d, i64(k), i64(k) * 3) }
	for k in 0 ..< 6 {
		s := string_of_int(i64(k) + 100)
		dict_set(&d, s, i64(k))
		n := name_of(k == 0 ? "" : "check_dict_key")
		dict_set(&d, n, i64(k))
		destroy[.STRING](&s)
		destroy[.STRING_NAME](&n)
	}
	for f in ([4]f64{0.5, -1, 1e300, 0}) { dict_set(&d, f, f) }
	dict_set(&d, true, 1)
	dict_set(&d, false, 0)
	dict_set(&d, Variant{}, 2)

	e := dictionary_new()
	defer destroy[.DICTIONARY](&e)
	dict_set(&e, 1, 1)
	ek := variant(i64(1))
	dictionary_erase(&e, ek)

	no_class: StringName
	no_script: Variant
	t := dictionary_new()
	defer destroy[.DICTIONARY](&t)
	gde.dictionary_set_typed(&t, .INT, &no_class, &no_script, .FLOAT, &no_class, &no_script)

	dict_layout_known = name_text_ok && dict_holds(&d) &&
		dict_map(&e).size == 0 && dictionary_size(&e) == 0 &&
		dict_key_type(&t) == .INT && dict_key_type(&d) == .NIL &&
		dict_value_type(&t) == .FLOAT && dict_value_type(&d) == .NIL
	if !dict_layout_known { return }
	// The lookups themselves, which need the layout known.
	keys := dictionary_keys(&d)
	defer destroy[.ARRAY](&keys)
	el := dict_map(&d).head
	for &k in array_stored(&keys) {
		found, ok := dict_lookup(&d, &k)
		if !ok || found != el { dict_layout_known = false; break }
		el = el.next
	}
}

// Whether `d`'s HashMap holds what the engine says it does: its size, and its elements linked in the
// order of its key list, each key and value the engine's.
@(private)
dict_holds :: proc "contextless" (d: ^Dictionary) -> bool {
	m := dict_map(d)
	n := dictionary_size(d)
	if i64(m.size) != n || m.elements == nil || m.capacity_idx >= len(DICT_PRIMES) { return false }
	keys := dictionary_keys(d)
	defer destroy[.ARRAY](&keys)
	values := dictionary_values(d)
	defer destroy[.ARRAY](&values)
	ks, vs := array_stored(&keys), array_stored(&values)
	if i64(len(ks)) != n || i64(len(vs)) != n { return false }
	el := m.head
	for i in 0 ..< n {
		if el == nil { return false }
		if gde.variant_hash_compare(&el.key, &ks[i]) == 0 || gde.variant_hash_compare(&el.value, &vs[i]) == 0 { return false }
		if i == n - 1 && el != m.tail { return false }
		el = el.next
	}
	return el == nil
}
