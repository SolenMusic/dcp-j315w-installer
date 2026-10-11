// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#include <arpa/inet.h>
#include <unistd.h>

static NSString *const printingPath = @"/Library/Printers/DCPJ315WCUPS/rastertodcpj315w";
static NSString *const scannerPath = @"/Library/Application Support/DCPJ315WInstaller/Scanner/build/DCPJ315WAirScanBridge.app";
static BOOL validIP(NSString *s) { struct in_addr address; return s && inet_pton(AF_INET,s.UTF8String,&address)==1; }
static NSString *shellQuote(NSString *s) { return [NSString stringWithFormat:@"'%@'",[s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]; }
static NSString *appleQuote(NSString *s) { return [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]; }

@interface Setup : NSObject <NSApplicationDelegate,NSNetServiceBrowserDelegate,NSNetServiceDelegate>
@property NSWindow *window;
@property NSTextField *address, *status, *installed;
@property NSButton *printing, *scanning, *configure, *remove, *discover, *removeTools;
@property NSNetServiceBrowser *browser;
@property NSMutableArray<NSNetService *> *services;
@property NSMutableSet<NSString *> *found;
@property BOOL busy;
@property NSString *discoveryError;
@end
@implementation Setup
- (NSTextField *)label:(NSString *)text {
  NSTextField *v=[NSTextField wrappingLabelWithString:text]; v.font=[NSFont systemFontOfSize:13]; v.maximumNumberOfLines=3; return v;
}
- (NSButton *)button:(NSString *)title action:(SEL)action {
  return [NSButton buttonWithTitle:title target:self action:action];
}
- (BOOL)exists:(NSString *)path { return [NSFileManager.defaultManager fileExistsAtPath:path]; }
- (NSString *)agent { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/org.dcpj315w.scan.airscan.plist"]; }
- (void)refresh {
  BOOL p=[self exists:printingPath], s=[self exists:scannerPath], active=[self exists:self.agent];
  self.installed.stringValue=[NSString stringWithFormat:@"Printing: %@   •   Scanning: %@",p?@"installed":@"not installed",active?@"configured for this user":(s?@"ready to configure":@"not installed")];
  self.printing.enabled=!self.busy && p;
  self.scanning.enabled=!self.busy && (s||active);
  if (!p) self.printing.state=NSControlStateValueOff;
  if (!s&&!active) self.scanning.state=NSControlStateValueOff;
  self.configure.enabled=!self.busy;
  self.remove.enabled=!self.busy;
  self.discover.enabled=!self.busy;
  self.removeTools.enabled=!self.busy && !p && !s && !active;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,560,450) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
  self.window.title=@"DCP-J315W Setup";
  NSStackView *stack=[NSStackView stackViewWithViews:@[]]; stack.orientation=NSUserInterfaceLayoutOrientationVertical; stack.alignment=NSLayoutAttributeLeading; stack.spacing=14; stack.translatesAutoresizingMaskIntoConstraints=NO;
  [self.window.contentView addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:24],[stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-24],[stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:24]]];
  NSTextField *heading=[self label:@"Printing and scanning over Wi-Fi"]; heading.font=[NSFont systemFontOfSize:21 weight:NSFontWeightSemibold]; [stack addArrangedSubview:heading];
  [stack addArrangedSubview:[self label:@"Choose installed components to configure or remove. USB/direct wired connections are not supported yet."]];
  self.installed=[self label:@""]; [stack addArrangedSubview:self.installed];
  self.printing=[NSButton checkboxWithTitle:@"Printing (this Mac)" target:nil action:nil]; self.printing.state=NSControlStateValueOn;
  self.scanning=[NSButton checkboxWithTitle:@"Scanning (this user)" target:nil action:nil]; self.scanning.state=NSControlStateValueOn;
  [stack addArrangedSubview:[NSStackView stackViewWithViews:@[self.printing,self.scanning]]];
  self.address=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,300,25)]; self.address.placeholderString=@"Printer IPv4 address";
  [self.address.widthAnchor constraintEqualToConstant:290].active=YES;
  NSDictionary *agent=[NSDictionary dictionaryWithContentsOfFile:self.agent]; NSArray *args=agent[@"ProgramArguments"];
  if (args.count>=3 && validIP(args[2])) self.address.stringValue=args[2];
  self.discover=[self button:@"Find on Network" action:@selector(find:)];
  [stack addArrangedSubview:[NSStackView stackViewWithViews:@[self.address,self.discover]]];
  self.configure=[self button:@"Configure Selected" action:@selector(configureSelected:)]; self.configure.keyEquivalent=@"\r";
  self.remove=[self button:@"Remove Selected…" action:@selector(removeSelected:)];
  [stack addArrangedSubview:[NSStackView stackViewWithViews:@[self.configure,self.remove]]];
  self.status=[self label:@"Printing changes need administrator authentication. Scanning runs in your account and starts at login."]; [stack addArrangedSubview:self.status];
  [stack addArrangedSubview:[self label:@"Saved scans, diagnostic logs and unrelated printer queues are preserved when removing these drivers."]];
  self.removeTools=[self button:@"Remove Setup App…" action:@selector(removeSetup:)]; [stack addArrangedSubview:self.removeTools];
  [self refresh]; [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
- (void)find:(id)sender {
  (void)sender;
  [self.browser stop]; self.services=[NSMutableArray array]; self.found=[NSMutableSet set]; self.discoveryError=nil;
  self.status.stringValue=@"Looking for a DCP-J315W on your network…";
  self.browser=[NSNetServiceBrowser new]; self.browser.delegate=self;
  [self.browser scheduleInRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  [self.browser searchForServicesOfType:@"_pdl-datastream._tcp." inDomain:@"local."];
  NSNetServiceBrowser *current=self.browser;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
    if (self.browser!=current) return;
    [current stop];
    if (!self.found.count) self.status.stringValue=self.discoveryError ?: @"No DCP-J315W found. Check Wi-Fi and power, or enter its IPv4 address.";
    else if (self.found.count>1) { self.address.stringValue=@""; self.status.stringValue=[NSString stringWithFormat:@"Several printers found: %@. Enter the address you want.",[[self.found allObjects] componentsJoinedByString:@", "]]; }
  });
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)more {
  (void)browser; (void)more; NSLog(@"DCP-J315W discovery: service located"); [self.services addObject:service]; service.delegate=self;
  [service scheduleInRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  [service resolveWithTimeout:5];
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary *)error {
  (void)browser; NSLog(@"DCP-J315W discovery: browse error %@",error[NSNetServicesErrorCode]);
  self.discoveryError=@"Network discovery is unavailable. Check this app's Local Network permission in System Settings, or enter the printer's IPv4 address.";
  self.status.stringValue=self.discoveryError;
}
- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)error {
  (void)service; NSLog(@"DCP-J315W discovery: resolve error %@",error[NSNetServicesErrorCode]);
}
- (void)netServiceDidResolveAddress:(NSNetService *)service {
  if (self.busy) return;
  NSDictionary *txt=[NSNetService dictionaryFromTXTRecordData:service.TXTRecordData ?: [NSData data]];
  NSString *model=[[NSString alloc] initWithData:txt[@"ty"] ?: [NSData data] encoding:NSUTF8StringEncoding];
  NSString *idText=[[NSString alloc] initWithData:txt[@"usb_MDL"] ?: [NSData data] encoding:NSUTF8StringEncoding];
  BOOL matching=(model.length && [model caseInsensitiveCompare:@"Brother DCP-J315W"]==NSOrderedSame) || (idText.length && [idText caseInsensitiveCompare:@"DCP-J315W"]==NSOrderedSame) || [service.name caseInsensitiveCompare:@"Brother DCP-J315W"]==NSOrderedSame;
  NSLog(@"DCP-J315W discovery: resolved (recognized=%d, addresses=%lu)",matching,(unsigned long)service.addresses.count);
  if (!matching) return;
  for (NSData *data in service.addresses) {
    if (data.length<sizeof(struct sockaddr_in)) continue;
    const struct sockaddr_in *a=data.bytes; if (a->sin_family!=AF_INET) continue;
    uint32_t ip=ntohl(a->sin_addr.s_addr); if (!ip || (ip>>24)==127 || (ip>>28)==14) continue;
    char text[INET_ADDRSTRLEN]; if (!inet_ntop(AF_INET,&a->sin_addr,text,sizeof(text))) continue;
    [self.found addObject:[NSString stringWithUTF8String:text]];
  }
  if (self.found.count==1) { self.address.stringValue=self.found.anyObject; self.status.stringValue=@"Printer found. Choose Configure Selected."; }
}
- (NSString *)script:(NSString *)name { return [NSBundle.mainBundle pathForResource:name ofType:@"sh" inDirectory:@"scripts"]; }
- (BOOL)runScript:(NSString *)name arguments:(NSArray<NSString *> *)args error:(NSString **)error {
  NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:@"/bin/bash"];
  NSMutableArray *arguments=[NSMutableArray arrayWithObject:[self script:name]]; [arguments addObjectsFromArray:args]; task.arguments=arguments;
  NSPipe *pipe=[NSPipe pipe]; task.standardOutput=pipe; task.standardError=pipe;
  NSError *failure=nil; if (![task launchAndReturnError:&failure]) { *error=failure.localizedDescription; return NO; }
  NSData *output=[pipe.fileHandleForReading readDataToEndOfFile]; [task waitUntilExit];
  if (task.terminationStatus) { *error=[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] ?: @"Operation failed."; return NO; }
  return YES;
}
- (BOOL)admin:(NSArray<NSString *> *)commands error:(NSString **)error {
  NSString *shell=[@"set -e\n" stringByAppendingString:[commands componentsJoinedByString:@"\n"]];
  NSString *source=[NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges",appleQuote(shell)];
  NSAppleScript *script=[[NSAppleScript alloc] initWithSource:source]; NSDictionary *failure=nil;
  if (![script executeAndReturnError:&failure]) { *error=failure[NSAppleScriptErrorMessage] ?: @"Administrator operation was cancelled or failed."; return NO; }
  return YES;
}
- (NSString *)command:(NSString *)script argument:(NSString *)arg {
  NSString *command=[@"/bin/bash " stringByAppendingString:shellQuote([self script:script])];
  return arg ? [command stringByAppendingFormat:@" %@",shellQuote(arg)] : command;
}
- (void)configureSelected:(id)sender {
  (void)sender;
  BOOL p=self.printing.state==NSControlStateValueOn, s=self.scanning.state==NSControlStateValueOn;
  NSString *ip=self.address.stringValue;
  if ((!p&&!s) || !validIP(ip)) { self.status.stringValue=@"Select a component and enter a numeric IPv4 address."; return; }
  if (s&&![self exists:scannerPath]) { self.status.stringValue=@"Install the Scanning component before configuring it."; return; }
  self.busy=YES; [self refresh]; [self.browser stop]; self.status.stringValue=@"Configuring selected components…";
  NSString *error=nil;
  if (p&&![self admin:@[[self command:@"configure-printer" argument:ip]] error:&error]) { self.busy=NO; [self refresh]; self.status.stringValue=error; return; }
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
    NSString *failure=nil; BOOL ok=!s || [self runScript:@"configure-scanner" arguments:@[ip] error:&failure];
    dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; [self refresh]; self.status.stringValue=ok?@"Configured. Choose DCP-J315W CUPS Driver for printing and DCP-J315W Open Scanner in Image Capture.":failure; });
  });
}
- (void)removeSelected:(id)sender {
  (void)sender;
  BOOL p=self.printing.state==NSControlStateValueOn, s=self.scanning.state==NSControlStateValueOn;
  if (!p&&!s) { self.status.stringValue=@"Select the components to remove."; return; }
  NSAlert *alert=[NSAlert new]; alert.messageText=@"Remove the selected components?";
  alert.informativeText=@"Printing removes this driver's queues and files from this Mac. Scanning removes this account's helper and shared installation files; other accounts' configured helpers remain. Saved scans and unrelated queues are preserved.";
  [alert addButtonWithTitle:@"Remove"]; [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal]!=NSAlertFirstButtonReturn) return;
  self.busy=YES; [self refresh]; [self.browser stop]; NSString *error=nil;
  NSMutableArray *commands=[NSMutableArray array];
  if (p&&[self exists:printingPath]) [commands addObject:[self command:@"remove-printer" argument:nil]];
  if (s&&[self exists:scannerPath]) [commands addObject:[self command:@"remove-scanner-files" argument:nil]];
  if (commands.count&&![self admin:commands error:&error]) { self.busy=NO; [self refresh]; self.status.stringValue=error; return; }
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
    NSString *failure=nil; BOOL ok=!s || [self runScript:@"remove-scanner" arguments:@[] error:&failure];
    dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; [self refresh]; self.status.stringValue=ok?@"Selected components removed. Saved documents were preserved.":failure; });
  });
}
- (void)removeSetup:(id)sender {
  (void)sender; NSAlert *alert=[NSAlert new]; alert.messageText=@"Remove DCP-J315W Setup?";
  alert.informativeText=@"The setup app and its package receipt will be removed. You can reinstall it from the combined installer.";
  [alert addButtonWithTitle:@"Remove"]; [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal]!=NSAlertFirstButtonReturn) return;
  NSString *error=nil; if ([self admin:@[[self command:@"remove-tools" argument:nil]] error:&error]) [NSApp terminate:nil]; else self.status.stringValue=error;
}
@end
int main(int argc,const char **argv) {
  @autoreleasepool {
    if (argc==2&&!strcmp(argv[1],"--self-test")) {
      if (!validIP(@"192.0.2.10") || validIP(@"1.2.3.999") || validIP(@"1.2.3.4;false") || validIP(@"hostname.local")) return 1;
      if (![shellQuote(@"a'b") isEqualToString:@"'a'\\''b'"]) return 1;
      puts("PASS: address validation and shell argument quoting"); return 0;
    }
    if (geteuid()==0) { fputs("Run DCP-J315W Setup as the logged-in user.\n",stderr); return 2; }
    NSApplication *app=[NSApplication sharedApplication]; [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    Setup *delegate=[Setup new]; app.delegate=delegate; [app run];
  }
  return 0;
}
