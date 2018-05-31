//
//  TaskBrowserViewController.swift
//  mPower2
//
//  Copyright © 2018 Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import UIKit
import Research
import MotorControl
import BridgeApp

protocol TaskBrowserViewControllerDelegate {
    func taskBrowserToggleVisibility()
    func taskBrowserTabSelected()
}

class TaskBrowserViewController: UIViewController, RSDTaskViewControllerDelegate, TaskBrowserTabViewDelegate {
    
    // Used by our potential parent VC to show/hide our collectionView
    class func tabsHeight() -> CGFloat {
        return 50.0
    }
    
    public let kMinCellHorizontalSpacing: CGFloat = 5.0
    public var delegate: TaskBrowserViewControllerDelegate?
    public var scheduleManagers: [SBAScheduleManager]?
    
    open var shouldShowTopShadow: Bool {
        return true
    }
    open var shouldShowTabs: Bool {
        guard let scheduleManagers = scheduleManagers else {
            return false
        }
        return scheduleManagers.count > 1
    }
    open var tasks: [RSDTaskInfo] {
        guard let group = selectedScheduleManager?.activityGroup else {
            return [RSDTaskInfo]()
        }
        return group.tasks
    }
    
    func scheduleManager(with identifier: String) -> SBAScheduleManager? {
        return scheduleManagers?.first(where: { $0.identifier == identifier })
    }

    private var selectedScheduleManager: SBAScheduleManager!
    
    @IBOutlet weak var tabButtonStackView: UIStackView!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var ruleView: UIView!
    @IBOutlet weak var shadowView: RSDShadowGradient!
    @IBOutlet weak var tabsViewHeightConstraint: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
    }
    
    func setupView() {
        
        // Remove existing managed subviews from tabBar stackView
        tabButtonStackView.arrangedSubviews.forEach({ $0.removeFromSuperview() })
        
        // Let's select the first task group by default.
        selectedScheduleManager = scheduleManagers?.first
        
        // Create tabs for each schedule manager
        scheduleManagers?.forEach { (manager) in
            manager.reloadData()
            let tabView = TaskBrowserTabView(frame: .zero, taskGroupIdentifier: manager.identifier)
            tabView.title = manager.activityGroup?.title
            tabView.delegate = self
            tabView.isSelected = (manager.identifier == selectedScheduleManager.identifier)
            tabButtonStackView.addArrangedSubview(tabView)
            NotificationCenter.default.addObserver(forName: .SBAUpdatedScheduledActivities, object: manager, queue: OperationQueue.main) { (notification) in
                self.collectionView.reloadData()
            }
        }
        
        // set the tabView height and hide or show it, along with the rule just below
        tabsViewHeightConstraint.constant = shouldShowTabs ? TaskBrowserViewController.tabsHeight() : 0.0
        tabButtonStackView.isHidden = !shouldShowTabs
        ruleView.isHidden = !shouldShowTabs

        // Hide or show our shadow and rule views
        shadowView.isHidden = !shouldShowTopShadow

        // Reload our data
        collectionView.reloadData()
    }
    
    func startTask(for taskInfo: RSDTaskInfo) {
        let (taskPath, _, _) = selectedScheduleManager.instantiateTaskPath(for: taskInfo)
        let vc = RSDTaskViewController(taskPath: taskPath)
        vc.delegate = self
        self.present(vc, animated: true, completion: nil)
    }
    
    // MARK: Instance methods
    public func showSelectionIndicator(visible: Bool) {
        // Iterate all of our tab views and change alpha
        tabButtonStackView.arrangedSubviews.forEach { (subView) in
            if let tabView = subView as? TaskBrowserTabView {
                tabView.rule.alpha = visible ? 1.0 : 0.0
            }
        }
    }
    
    // MARK: RSDTaskViewControllerDelegate
    func taskController(_ taskController: RSDTaskController, didFinishWith reason: RSDTaskFinishReason, error: Error?) {
        // dismiss the view controller
        (taskController as? UIViewController)?.dismiss(animated: true) {
        }
        // Let the schedule manager handle the cleanup.
        selectedScheduleManager.taskController(taskController, didFinishWith: reason, error: error)
    }
    
    func taskController(_ taskController: RSDTaskController, readyToSave taskPath: RSDTaskPath) {
        selectedScheduleManager.taskController(taskController, readyToSave: taskPath)
    }
    
    func taskController(_ taskController: RSDTaskController, asyncActionControllerFor configuration: RSDAsyncActionConfiguration) -> RSDAsyncActionController? {
        return selectedScheduleManager.taskController(taskController, asyncActionControllerFor:configuration)
    }

    // MARK: TaskBrowserTabViewDelegate
    func taskGroupSelected(identifier: String) {
        
        guard let newManager = scheduleManager(with: identifier) else {
            return
        }
        
        // If this is the currently selected task group - meaning the user tapped the selected tab,
        // we tell our delegate to toggle visibility
        if newManager.identifier == selectedScheduleManager?.identifier,
            let delegate = delegate {
            delegate.taskBrowserToggleVisibility()
        }
        else {
            // Save our selected task group and reload collection
            selectedScheduleManager = newManager
            collectionView.reloadData()
            
            // Now update the isSelected value of all the tabs
            tabButtonStackView.arrangedSubviews.forEach {
                if let tabView = $0 as? TaskBrowserTabView {
                    tabView.isSelected = tabView.taskGroupIdentifier == identifier
                }
            }
            
            // Tell our delegate that a tab was selected. It may be that we are hidden and the
            // parent view might like to show us again
            if let delegate = delegate {
                delegate.taskBrowserTabSelected()
            }
        }
    }
}

extension TaskBrowserViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    @objc
    open var collectionCellIdentifier: String {
        return "TaskCollectionViewCell"
    }
    
    // MARK: UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tasks.count
    }
    
    // MARK: UICollectionViewDelegate
    open func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: collectionCellIdentifier, for: indexPath) as? TaskCollectionViewCell
        let task = tasks[indexPath.row]
        cell?.image = task.iconWhite
        cell?.title = task.title?.uppercased()
        cell?.isCompleted = selectedScheduleManager.isCompleted(for: task, on: Date())
        return cell ?? UICollectionViewCell()
    }
    
    @objc
    open func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        // Get our task and present it
        startTask(for: tasks[indexPath.row])
    }
    
    @objc
    open func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return horizontalSpacing(for: collectionView, layout: collectionViewLayout)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
                return collectionView.contentInset
        }

        let spacing = horizontalSpacing(for: collectionView, layout: collectionViewLayout)
        return UIEdgeInsetsMake(flowLayout.sectionInset.top, spacing, flowLayout.sectionInset.bottom, spacing)
    }
    
    @objc
    open func horizontalSpacing(for collectionView: UICollectionView, layout: UICollectionViewLayout) -> CGFloat {
        guard let flowLayout = layout as? UICollectionViewFlowLayout else {
                return kMinCellHorizontalSpacing
        }
        
        // We want our cells to be laid out in one horizontal row, with scrolling if necessary.
        // The default layout behavior for UICollectionView is to layout the cells from left to right.
        // In our case, we may want the cells centered horizontally in the view, which means we must
        // calculate the desired spacing so the cells appear centered. However, we may have more cells
        // than can fit in the collectionView.bounds, in which case we want the cells laid out from
        // left to right and extending beyond the bounds of the collectionView, then the user can scroll
        // horizontally as needed. In this case, we want the last visible cell on the right side of the
        // view to be just partially visible - ie. half on screen, half off screen - to inform the user
        // that they can scroll to the right to get more.
        
        let totalCellWidth = flowLayout.itemSize.width * CGFloat(tasks.count)
        let totalSpacingWidth = kMinCellHorizontalSpacing * (CGFloat(tasks.count) + 1)
        let totalWidth = totalCellWidth + totalSpacingWidth
        
        if totalWidth > collectionView.bounds.width {
            // Find a spacing value that results in the last visible cell being positioned half off-screen
            let availableWidth = collectionView.bounds.width - (flowLayout.itemSize.width / 2)
            let qtyCellsThatFit = floorf(Float(availableWidth / (flowLayout.itemSize.width + kMinCellHorizontalSpacing)))
            let spacingAdjusted = (availableWidth - (CGFloat(qtyCellsThatFit) * flowLayout.itemSize.width)) / CGFloat(qtyCellsThatFit + 1)
            return spacingAdjusted
        }
        else {
            // All cells will fit, so use a spacing value that centers them horizontally
            let cellCount = CGFloat(tasks.count)
            return (collectionView.bounds.width - (cellCount * flowLayout.itemSize.width)) / (cellCount + 1.0)
        }
    }
}

protocol TaskBrowserTabViewDelegate {
    func taskGroupSelected(identifier: String)
}

@IBDesignable class TaskBrowserTabView: UIView {
    
    public var taskGroupIdentifier: String?
    public var delegate: TaskBrowserTabViewDelegate?
    
    @IBInspectable public var title: String? {
        didSet {
            label.text = title
        }
    }
    @IBInspectable public var isSelected: Bool = false {
        didSet {
            rule.isHidden = !isSelected
        }
    }
    
    public let rule: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.royal500
        return view
    }()
    let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.boldSystemFont(ofSize: 16.0)
        label.numberOfLines = 0
        label.textColor = UIColor.darkGray
        label.textAlignment = .center
        return label
    }()

    public init(frame: CGRect, taskGroupIdentifier: String) {
        super.init(frame: frame)
        self.taskGroupIdentifier = taskGroupIdentifier
        commonInit()
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    func commonInit() {
        
        // Add our label
        addSubview(label)
        label.rsd_alignAllToSuperview(padding: 0.0)
        
        // Add our rule
        addSubview(rule)
        rule.rsd_makeHeight(.equal, 4.0)
        rule.rsd_alignToSuperview([.leading, .trailing, .bottom], padding: 0.0)
        
        // Add a button
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tabSelected), for: .touchUpInside)
        addSubview(button)
        button.rsd_alignAllToSuperview(padding: 0.0)
    }
    
    override open func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        commonInit()
        setNeedsDisplay()
    }
    
    @objc
    func tabSelected() {
        if let delegate = delegate,
            let taskGroupIdentifier = taskGroupIdentifier {
            delegate.taskGroupSelected(identifier: taskGroupIdentifier)
        }
    }
}

class TaskCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var completedCheckmark: UIImageView!
    
    public var title: String? {
        didSet {
            label.text = title
        }
    }
    public var image: UIImage? {
        didSet {
            imageView.image = image
        }
    }
    public var isCompleted: Bool = false {
        didSet {
            completedCheckmark.isHidden = !isCompleted
        }
    }
 }

// Use this just so the corner radius show's up in Interface Builder
@IBDesignable
class RoundedCornerView: UIView {
    @IBInspectable var cornerRadius: CGFloat = 0.0 {
        didSet {
            layer.cornerRadius = cornerRadius
        }
    }
}
