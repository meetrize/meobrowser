#import <Cocoa/Cocoa.h>

@interface MainWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) IBOutlet NSSearchField *searchField;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSTableView *sidebarTableView;

@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSSecureTextField *passwordField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *themePopUp;
@property (nonatomic, strong) IBOutlet NSButton *notifyCheckbox;
@property (nonatomic, strong) IBOutlet NSSlider *volumeSlider;
@property (nonatomic, strong) IBOutlet NSDatePicker *datePicker;
@property (nonatomic, strong) IBOutlet NSColorWell *colorWell;
@property (nonatomic, strong) IBOutlet NSStepper *stepper;

@property (nonatomic, strong) IBOutlet NSTextView *outputTextView;
@property (nonatomic, strong) IBOutlet NSProgressIndicator *progressBar;
@property (nonatomic, strong) IBOutlet NSProgressIndicator *progressSpinner;
@property (nonatomic, strong) IBOutlet NSLevelIndicator *levelIndicator;
@property (nonatomic, strong) IBOutlet NSImageView *previewImageView;

@property (nonatomic, strong) IBOutlet NSButton *actionButton;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *segmentControl;
@property (nonatomic, strong) IBOutlet NSTabView *mainTabView;

- (IBAction)onActionButton:(id)sender;
- (IBAction)onShowAlert:(id)sender;
- (IBAction)onSliderChanged:(id)sender;
- (IBAction)onCheckboxChanged:(id)sender;
- (IBAction)onSegmentChanged:(id)sender;
- (IBAction)onStepperChanged:(id)sender;

@end
