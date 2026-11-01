# TOON Format Examples

This directory contains various examples demonstrating the TOON format encoder and decoder.

## Examples

### Main Example (`example.dart`)
Basic example with a simple array of objects in tabular format.

**Output:**
```
=== Simple JSON Example ===
users[2]{id,name,role}:
  1,Alice,admin
  2,Bob,user

Decoded JSON:
{
  "users": [
    {
      "id": 1.0,
      "name": "Alice",
      "role": "admin"
    },
    {
      "id": 2.0,
      "name": "Bob",
      "role": "user"
    }
  ]
}
```

### 1. Simple JSON (`1_simple_json.dart`)
Basic example with a simple object containing primitive values (string, number, boolean).

**Output:**
```
=== 1. Simple JSON Example ===

TOON Format:
name: John Doe
age: 30
active: true
score: 95.5
email: john@example.com

Decoded JSON:
{
  "name": "John Doe",
  "age": 30.0,
  "active": true,
  "score": 95.5,
  "email": "john@example.com"
}
```

### 2. Flat List (`2_flat_list.dart`)
Demonstrates arrays with different data types (strings, numbers, booleans, null).

**Output:**
```
=== 2. Flat List with Different Data Types ===

TOON Format:
items[7]: apple,42,3.14,true,false,null,cherry

Decoded JSON:
{
  "items": [
    "apple",
    42.0,
    3.14,
    true,
    false,
    null,
    "cherry"
  ]
}
```

### 3. Nested Children (`3_nested_children.dart`)
Shows nested objects with multiple levels of hierarchy and different data types.

**Output:**
```
=== 3. Nested JSON with Children ===

TOON Format:
user:
  id: 1
  name: Alice
  active: true
  profile:
    age: 28
    email: alice@example.com
    preferences:
      theme: dark
      notifications: true
      score: 95.5
  tags[3]: developer,designer,writer

Decoded JSON:
{
  "user": {
    "id": 1.0,
    "name": "Alice",
    "active": true,
    "profile": {
      "age": 28.0,
      "email": "alice@example.com",
      "preferences": {
        "theme": "dark",
        "notifications": true,
        "score": 95.5
      }
    },
    "tags": [
      "developer",
      "designer",
      "writer"
    ]
  }
}
```

### 4. Tabular Array (`4_tabular_array.dart`)
Best use case: arrays of objects with uniform structure, displayed in compact tabular format.

**Output:**
```
=== 4. Tabular Array (Array of Objects) ===

TOON Format (Tabular):
products[3]{id,name,price,stock}:
  1,Widget,9.99,100
  2,Gadget,19.99,50
  3,Thingy,29.99,25

Decoded JSON:
{
  "products": [
    {
      "id": 1.0,
      "name": "Widget",
      "price": 9.99,
      "stock": 100.0
    },
    {
      "id": 2.0,
      "name": "Gadget",
      "price": 19.99,
      "stock": 50.0
    },
    {
      "id": 3.0,
      "name": "Thingy",
      "price": 29.99,
      "stock": 25.0
    }
  ]
}
```

### 5. Mixed Arrays (`5_mixed_arrays.dart`)
Non-uniform arrays containing objects, primitives, and nested arrays (uses list format).

**Output:**
```
=== 5. Mixed Arrays (Non-uniform) ===

TOON Format (List format for mixed arrays):
items[6]:
  - simple string
  - 42
  - name: object item
    value: 100
  - [2]: nested,array
  - true
  - id: 1
    data[3]: 1,2,3

Decoded JSON:
{
  "items": [
    "simple string",
    42.0,
    {
      "name": "object item",
      "value": 100.0
    },
    [
      "nested",
      "array"
    ],
    true,
    {
      "id": 1.0,
      "data": [
        1.0,
        2.0,
        3.0
      ]
    }
  ]
}

Array of Arrays:
matrix[3]:
  - [3]: 1,2,3
  - [3]: 4,5,6
  - [3]: 7,8,9
```

### 6. Custom Options (`6_custom_options.dart`)
Demonstrates various encoding options:
- Different delimiters (comma, tab, pipe)
- Length markers
- Custom indentation

**Output:**
```
=== 6. Custom Encoding Options ===

Default (comma delimiter):
items[2]{sku,name,qty,price}:
  A1,Widget,2,9.99
  B2,Gadget,1,14.5

Tab delimiter:
items[2	]{sku	name	qty	price}:
  A1	Widget	2	9.99
  B2	Gadget	1	14.5

Pipe delimiter:
items[2|]{sku|name|qty|price}:
  A1|Widget|2|9.99
  B2|Gadget|1|14.5

With length marker (#):
items[#2]{sku,name,qty,price}:
  A1,Widget,2,9.99
  B2,Gadget,1,14.5

Custom indent (4 spaces):
items[2]{sku,name,qty,price}:
    A1,Widget,2,9.99
    B2,Gadget,1,14.5

Combined (tab + length marker):
items[#2	]{sku	name	qty	price}:
  A1	Widget	2	9.99
  B2	Gadget	1	14.5
```

### 7. Decoding Examples (`7_decoding_examples.dart`)
Shows how to decode TOON strings back to Dart objects.

**Output:**
```
=== 7. Decoding Examples ===

TOON Input:
name: John Doe
age: 30
active: true

Decoded JSON:
{
  "name": "John Doe",
  "age": 30.0,
  "active": true
}

Tabular TOON Input:
products[3]{id,name,price}:
  1,Widget,9.99
  2,Gadget,19.99
  3,Thingy,29.99

Decoded JSON:
{
  "products": [
    {
      "id": 1.0,
      "name": "Widget",
      "price": 9.99
    },
    {
      "id": 2.0,
      "name": "Gadget",
      "price": 19.99
    },
    {
      "id": 3.0,
      "name": "Thingy",
      "price": 9.99
    }
  ]
}

Inline Array TOON Input:
tags[3]: reading,gaming,coding

Decoded JSON:
{
  "tags": [
    "reading",
    "gaming",
    "coding"
  ]
}

Nested TOON Input:
user:
  id: 1
  name: Alice
  profile:
    age: 28
    email: alice@example.com

Decoded JSON:
{
  "user": {
    "id": 1.0,
    "name": "Alice",
    "profile": {
      "age": 28.0,
      "email": "alice@example.com"
    }
  }
}
```

### 8. Edge Cases (`8_edge_cases.dart`)
Handles edge cases like:
- Empty structures
- Special strings requiring quoting
- Number edge cases
- Deeply nested structures

**Output:**
```
=== 8. Edge Cases ===

Empty object:


Empty array:
items[0]:

Special strings (need quoting):
values[8]: "hello, world","key: value","item[1]","item{field}","  spaced  ","true","null","123"

Number edge cases:
values[8]: 0,0,42,-42,3.14,-3.14,10000000000.0,-10000000000.0

Null and boolean values:
data[5]: true,false,null,string,42

Single item array:
items[1]: single

Deeply nested:
level1:
  level2:
    level3:
      level4:
        value: deep
```

## Running Examples

Run any example with fvm (Flutter Version Manager):

```bash
# Using fvm
fvm dart run example/example.dart
fvm dart run example/1_simple_json.dart
fvm dart run example/2_flat_list.dart
fvm dart run example/3_nested_children.dart
fvm dart run example/4_tabular_array.dart
fvm dart run example/5_mixed_arrays.dart
fvm dart run example/6_custom_options.dart
fvm dart run example/7_decoding_examples.dart
fvm dart run example/8_edge_cases.dart
```

**Note:** If you're not using fvm, you can use regular `dart` commands instead.

## Key Features Demonstrated

- **Tabular Format**: Most efficient for arrays of objects with uniform structure
- **List Format**: Used for mixed/non-uniform arrays
- **Inline Arrays**: Primitive arrays can be encoded inline
- **Nested Objects**: Supports arbitrary nesting levels
- **Custom Options**: Flexible encoding options (delimiters, length markers, indentation)
- **Edge Cases**: Handles empty structures, special strings, and various data types
