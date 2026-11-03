#import "IEBSourceCell.h"
@implementation IEBSourceCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    (void)style;
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    if (self) {
        BOOL hebrew = [NSBundle.mainBundle.preferredLocalizations.firstObject hasPrefix:@"he"];
        self.contentView.semanticContentAttribute =
            hebrew ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        _nameLabel.numberOfLines = 0;
        _timesLabel = [UILabel new];
        _timesLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _timesLabel.textColor = UIColor.secondaryLabelColor;
        _timesLabel.numberOfLines = 0;
        _percentLabel = [UILabel new];
        _percentLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular];
        _percentLabel.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
        _percentLabel.textAlignment = NSTextAlignmentRight;
        _percentLabel.adjustsFontSizeToFitWidth = YES;
        _percentLabel.minimumScaleFactor = 0.7;
        _sourceIcon = [UIImageView new];
        _sourceIcon.contentMode = UIViewContentModeScaleAspectFit;
        UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[ _nameLabel, _timesLabel ]];
        text.axis = UILayoutConstraintAxisVertical;
        text.spacing = 3;
        UIStackView *row =
            [[UIStackView alloc] initWithArrangedSubviews:@[ _sourceIcon, text, _percentLabel ]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 10;
        row.alignment = UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:row];
        NSLayoutConstraint *iconWidth = [_sourceIcon.widthAnchor constraintEqualToConstant:32];
        iconWidth.priority = 999;
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12], iconWidth,
            [_sourceIcon.heightAnchor constraintEqualToConstant:32],
            [_percentLabel.widthAnchor constraintEqualToConstant:72]
        ]];
        [text setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                              forAxis:UILayoutConstraintAxisHorizontal];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}
- (void)configureName:(NSString *)name
           percentage:(NSString *)percentage
              details:(NSString *)details
                 icon:(UIImage *)icon {
    self.nameLabel.text = name;
    self.percentLabel.text = percentage ?: @"";
    self.timesLabel.text = details;
    self.sourceIcon.image = icon;
    self.sourceIcon.hidden = icon == nil;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel =
        [@[ name ?: @"", percentage ?: @"", details ?: @"" ] componentsJoinedByString:@", "];
}
@end
