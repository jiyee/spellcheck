/*
 * Bar.h
 */

#define BarN [NSString stringWithFormat:@"%@", BarN]

@interface Bar : NSObject

// bar
// Bar
@property NSString *bar; // bar
@property NSString *bara;
@property NSString *foop;
@property NSString *barpTrue;
@property NSString *barpp;
@property NSString *barp1;
@property NSString *foo_true;
@property NSString *true_bar;
@property NSString *barTrue;
@property NSString *NSbar;
@property NSString *Bar;
@property NSString *Bar_True;
@property NSString *True_Bar;
@property NSString *BarTrue;
@property NSString *TrueBar;
@property NSString *TrueBarFalse;
@property NSString *bar2;
@property NSString *Foo1;
@property NSString *Bar1True;
@property NSString *Foo2;
@property NSString *Foo_2;
@property NSString *Bar2True;
@property int bar;
@property int barTrue;
@property int Bar;
@property int BarTrue;
@property int TrueBar;
@property int bar2;
@property int Foo2;
@property (atomic) int _fook;
@property (atomic) int fook_url;

- (void)bar:(NSString *)param1;
- (void)Bar:(NSString *)Bar;
- (void)Bar:(NSString *)param1 Foo2:(NSString *)Foo2;
- (void)BarTrue:(NSString *)param1 BarTrue2:(NSString *)Foo2;
- (void)BarTrue:(NSString *)param1 Bar2True:(NSString *)Bar2True;
- (void)BarTrue:(NSString *)param1 BarTrue2:(NSString *)param2;
- (void)Foop:(NSString *)param1;
- (void)Foop:(NSString *)param1 FooTrue3:(NSString *)Foo3;

bar // ([^a-z]|^)$token
Bar // ([^a-z]|^)$token
Foo2 // ([^a-z]|^)$token
bar2 // ([^a-z]|^)$token
#bar
	bar
foobar
bar bar // ([^a-z])$token
Bar bar // ([^a-z])$token
Foo2 bar // ([^a-z])$token

	_fook = fook
	_fook_url = _fook_url

foop
_foop = foop
self.foop
[self setFoop]
[self getFoop]
[self setBarp2]

@"bar"
@"foo_true"
@"true_bar"
@"barTrue"
@"NSbar"
@"Bar"
@"BarTrue"
@"Bar_True"
@"TrueBar"
@"True_Bar"
@"bar2"
@"Foo2"
@"Foo_2"
@"Bar2True"
@"True2Bar"
@"bar.jpg"

@selector(bar:)
@selector(Bar:)
@selector(foop:)
@selector(Bar:Foo2:)
@selector(BarTrue:BarTrue2:)

NSLog(@"%@", Foo4);

NSSelectorFromString(@"Bar");
NSSelectorFromString(@"BarTrue");
NSSelectorFromString(@"Bar:");
NSSelectorFromString(@"BarTrue:");
NSSelectorFromString(@"Bar:Foo2:");

Bar Foo2
[bar barTrue:True]

@end
