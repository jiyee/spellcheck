/*
 * Foo.h
 */

#define FooN [NSString stringWithFormat:@"%@", FooN]

@interface Foo : NSObject

// foo
// Foo
@property NSString *foo; // foo
@property NSString *fooa;
@property NSString *foop;
@property NSString *foopTrue;
@property NSString *foopp;
@property NSString *foop1;
@property NSString *foo_true;
@property NSString *true_foo;
@property NSString *fooTrue;
@property NSString *NSfoo;
@property NSString *Foo;
@property NSString *Foo_True;
@property NSString *True_Foo;
@property NSString *FooTrue;
@property NSString *TrueFoo;
@property NSString *TrueFooFalse;
@property NSString *foo2;
@property NSString *Foo1;
@property NSString *Foo1True;
@property NSString *Foo2;
@property NSString *Foo_2;
@property NSString *Foo2True;
@property int foo;
@property int fooTrue;
@property int Foo;
@property int FooTrue;
@property int TrueFoo;
@property int foo2;
@property int Foo2;
@property (atomic) int _fook;
@property (atomic) int fook_url;

- (void)foo:(NSString *)param1;
- (void)Foo:(NSString *)Foo;
- (void)Foo:(NSString *)param1 Foo2:(NSString *)Foo2;
- (void)FooTrue:(NSString *)param1 FooTrue2:(NSString *)Foo2;
- (void)FooTrue:(NSString *)param1 Foo2True:(NSString *)Foo2True;
- (void)FooTrue:(NSString *)param1 FooTrue2:(NSString *)param2;
- (void)Foop:(NSString *)param1;
- (void)Foop:(NSString *)param1 FooTrue3:(NSString *)Foo3;

foo // ([^a-z]|^)$token
Foo // ([^a-z]|^)$token
Foo2 // ([^a-z]|^)$token
foo2 // ([^a-z]|^)$token
#foo
	foo
foobar
foo bar // ([^a-z])$token
Foo bar // ([^a-z])$token
Foo2 bar // ([^a-z])$token

	_fook = fook
	_fook_url = _fook_url

foop
_foop = foop
self.foop
[self setFoop]
[self getFoop]
[self setFoop2]

@"foo"
@"foo_true"
@"true_foo"
@"fooTrue"
@"NSfoo"
@"Foo"
@"FooTrue"
@"Foo_True"
@"TrueFoo"
@"True_Foo"
@"foo2"
@"Foo2"
@"Foo_2"
@"Foo2True"
@"True2Foo"
@"foo.jpg"

@selector(foo:)
@selector(Foo:)
@selector(foop:)
@selector(Foo:Foo2:)
@selector(FooTrue:FooTrue2:)

NSLog(@"%@", Foo4);

NSSelectorFromString(@"Foo");
NSSelectorFromString(@"FooTrue");
NSSelectorFromString(@"Foo:");
NSSelectorFromString(@"FooTrue:");
NSSelectorFromString(@"Foo:Foo2:");

Foo Foo2
[foo fooTrue:True]

@end
