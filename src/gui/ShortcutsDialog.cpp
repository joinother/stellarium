/*
 * Stellarium
 * Copyright (C) 2012 Anton Samoylov
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Suite 500, Boston, MA  02110-1335, USA.
 */

#include <QDialog>
#include <QStandardItemModel>
#include <QDebug>
#include <QSignalBlocker>

#include "StelApp.hpp"
#include "StelGui.hpp"
#include "StelTranslator.hpp"
#include "StelActionMgr.hpp"
#include "ShortcutLineEdit.hpp"
#include "ShortcutsDialog.hpp"
#include "ui_shortcutsDialog.h"


ShortcutsFilterModel::ShortcutsFilterModel(QObject* parent) :
    QSortFilterProxyModel(parent)
{
	//
}

bool ShortcutsFilterModel::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const
{
#if (QT_VERSION>=QT_VERSION_CHECK(6,0,0))
	if (filterRegularExpression().pattern().isEmpty())
#else
	if (filterRegExp().pattern().isEmpty())
#endif
	{
		return true;
	}

#if (QT_VERSION>=QT_VERSION_CHECK(6,0,0))
	auto matches = [this](const QString& data)
	{
		return data.contains(filterRegularExpression());
	};
#else
	auto matches = [this](const QString& data)
	{
		return data.contains(filterRegExp());
	};
#endif

	auto matchesRow = [this, &matches](const QModelIndex& index)
	{
		if (!index.isValid())
			return false;
		for (int column = 0; column < sourceModel()->columnCount(index); ++column)
		{
			const QModelIndex cell = index.sibling(index.row(), column);
			if (matches(sourceModel()->data(cell, filterRole()).toString()) ||
			    matches(sourceModel()->data(cell, Qt::UserRole).toString()))
				return true;
		}
		return false;
	};

	if (source_parent.isValid())
	{
		const QModelIndex groupIndex = source_parent.sibling(source_parent.row(), 0);
		const QModelIndex actionIndex = sourceModel()->index(source_row, 0, source_parent);
		return matchesRow(groupIndex) || matchesRow(actionIndex);
	}

	const QModelIndex groupIndex = sourceModel()->index(source_row, 0, source_parent);
	if (matchesRow(groupIndex))
		return true;
	for (int row = 0; row < sourceModel()->rowCount(groupIndex); ++row)
	{
		if (filterAcceptsRow(row, groupIndex))
			return true;
	}
	return false;
}


ShortcutsDialog::ShortcutsDialog(QObject* parent) :
	StelDialog("Shortcuts", parent),
	ui(new Ui_shortcutsDialogForm),
	filterModel(new ShortcutsFilterModel(this)),
	mainModel(new QStandardItemModel(this))
{
	actionMgr = StelApp::getInstance().getStelActionManager();
}

ShortcutsDialog::~ShortcutsDialog()
{
	collisionItems.clear();
	delete ui;
	ui = nullptr;
}

void ShortcutsDialog::drawCollisions()
{
	QBrush brush(Qt::red);
	for (auto* item : std::as_const(collisionItems))
	{
		// change colors of all columns for better visibility
		item->setForeground(brush);
		QModelIndex index = item->index();
		mainModel->itemFromIndex(index.sibling(index.row(), 1))->setForeground(brush);
		mainModel->itemFromIndex(index.sibling(index.row(), 2))->setForeground(brush);
	}
}

void ShortcutsDialog::resetCollisions()
{
	QBrush brush =
#if (QT_VERSION>=QT_VERSION_CHECK(5,15,0))
		ui->shortcutsTreeView->palette().windowText();
#else
		ui->shortcutsTreeView->palette().brush(QPalette::Foreground);
#endif
	for (auto* item : std::as_const(collisionItems))
	{
		item->setForeground(brush);
		QModelIndex index = item->index();
		mainModel->itemFromIndex(index.sibling(index.row(), 1))->setForeground(brush);
		mainModel->itemFromIndex(index.sibling(index.row(), 2))->setForeground(brush);
	}
	collisionItems.clear();
	ui->primaryShortcutEdit->setProperty("collision", false);
	ui->altShortcutEdit->setProperty("collision", false);
}

void ShortcutsDialog::retranslate()
{
	if (dialog)
	{
		ui->retranslateUi(dialog);
		setModelHeader();
		updateTreeData();
	}
}

void ShortcutsDialog::initEditors()
{
	QModelIndex index = filterModel->mapToSource(ui->shortcutsTreeView->currentIndex());
	index = index.sibling(index.row(), 0);
	QStandardItem* currentItem = mainModel->itemFromIndex(index);
	QSignalBlocker primaryBlocker(ui->primaryShortcutEdit);
	QSignalBlocker altBlocker(ui->altShortcutEdit);
	resetCollisions();
	if (itemIsEditable(currentItem))
	{
		// current item is shortcut, not group (group items aren't selectable)
		ui->primaryShortcutEdit->setEnabled(true);
		ui->altShortcutEdit->setEnabled(true);
		ui->restoreDefaultsButton->setEnabled(true);
		// fill editors with item's shortcuts
		QVariant data = mainModel->data(index.sibling(index.row(), 1));
		ui->primaryShortcutEdit->setContents(data.value<QKeySequence>());
		data = mainModel->data(index.sibling(index.row(), 2));
		ui->altShortcutEdit->setContents(data.value<QKeySequence>());
		ui->primaryBackspaceButton->setEnabled(!ui->primaryShortcutEdit->isEmpty());
		ui->altBackspaceButton->setEnabled(!ui->altShortcutEdit->isEmpty());
		ui->applyButton->setEnabled(false);
	}
	else
	{
		// item is group, not shortcut
		ui->primaryShortcutEdit->setEnabled(false);
		ui->altShortcutEdit->setEnabled(false);
		ui->applyButton->setEnabled(false);
		ui->restoreDefaultsButton->setEnabled(false);
		ui->primaryShortcutEdit->setContents(QKeySequence());
		ui->altShortcutEdit->setContents(QKeySequence());
		ui->primaryBackspaceButton->setEnabled(false);
		ui->altBackspaceButton->setEnabled(false);
	}
	polish();
}

bool ShortcutsDialog::prefixMatchKeySequence(const QKeySequence& ks1,
                                             const QKeySequence& ks2)
{
	if (ks1.isEmpty() || ks2.isEmpty())
	{
		return false;
	}
	for (uint i = 0; i < static_cast<uint>(qMin(ks1.count(), ks2.count())); ++i)
	{
		if (ks1[i] != ks2[i])
		{
			return false;
		}
	}
	return true;
}

QList<QStandardItem*> ShortcutsDialog::findCollidingItems(QKeySequence ks)
{
	QList<QStandardItem*> result;
	for (int row = 0; row < mainModel->rowCount(); row++)
	{
		QStandardItem* group = mainModel->item(row, 0);
		if (!group->hasChildren())
			continue;
		for (int subrow = 0; subrow < group->rowCount(); subrow++)
		{
			QKeySequence primary(group->child(subrow, 1)
			                     ->data(Qt::DisplayRole).toString());
			QKeySequence secondary(group->child(subrow, 2)
			                       ->data(Qt::DisplayRole).toString());
			if (prefixMatchKeySequence(ks, primary) ||
			    prefixMatchKeySequence(ks, secondary))
				result.append(group->child(subrow, 0));
		}
	}
	return result;
}

void ShortcutsDialog::handleCollisions(ShortcutLineEdit *currentEdit)
{
	if (!currentEdit)
		return;
	resetCollisions();

	QModelIndex index =
	        filterModel->mapToSource(ui->shortcutsTreeView->currentIndex());
	index = index.sibling(index.row(), 0);
	QStandardItem* currentItem = mainModel->itemFromIndex(index);
	QList<QStandardItem*> currentCollisions = findCollidingItems(currentEdit->getKeySequence());
	QList<QStandardItem*> primaryCollisions = findCollidingItems(
	        ui->primaryShortcutEdit->getKeySequence());
	QList<QStandardItem*> altCollisions = findCollidingItems(
	        ui->altShortcutEdit->getKeySequence());
	collisionItems = primaryCollisions;
	for (auto* item : altCollisions)
	{
		if (!collisionItems.contains(item))
			collisionItems.append(item);
	}
	collisionItems.removeOne(currentItem);
	currentCollisions.removeOne(currentItem);
	primaryCollisions.removeOne(currentItem);
	altCollisions.removeOne(currentItem);
	ui->primaryShortcutEdit->setProperty("collision", !primaryCollisions.isEmpty());
	ui->altShortcutEdit->setProperty("collision", !altCollisions.isEmpty());
	if (!collisionItems.isEmpty())
	{
		drawCollisions();
		const QList<QStandardItem*>& scrollItems = currentCollisions.isEmpty() ? collisionItems : currentCollisions;
		if (!scrollItems.isEmpty())
		{
			QModelIndex first = filterModel->mapFromSource(scrollItems.first()->index());
			ui->shortcutsTreeView->scrollTo(first);
		}
	}
}

void ShortcutsDialog::handleChanges()
{
	// work only with changed editor
	ShortcutLineEdit* editor = qobject_cast<ShortcutLineEdit*>(sender());
	bool isPrimary = (editor == ui->primaryShortcutEdit);
	// updating clear buttons
	if (isPrimary)
	{
		ui->primaryBackspaceButton->setEnabled(!editor->isEmpty());
	}
	else
	{
		ui->altBackspaceButton->setEnabled(!editor->isEmpty());
	}
	// updating apply button
	QModelIndex index = filterModel->mapToSource(ui->shortcutsTreeView->currentIndex());
	handleCollisions(editor);
	bool changed = false;
	if (index.isValid())
	{
		const QKeySequence storedPrimary = mainModel->data(
		        index.sibling(index.row(), 1)).value<QKeySequence>();
		const QKeySequence storedAlt = mainModel->data(
		        index.sibling(index.row(), 2)).value<QKeySequence>();
		changed = ui->primaryShortcutEdit->getKeySequence() != storedPrimary ||
		          ui->altShortcutEdit->getKeySequence() != storedAlt;
	}
	const bool hasCollision = ui->primaryShortcutEdit->property("collision").toBool() ||
	                         ui->altShortcutEdit->property("collision").toBool();
	ui->applyButton->setEnabled(changed && !hasCollision);
	polish();
}

void ShortcutsDialog::applyChanges()
{
	// get ids stored in tree
	QModelIndex index = filterModel->mapToSource(ui->shortcutsTreeView->currentIndex());
	if (!index.isValid())
		return;
	index = index.sibling(index.row(), 0);
	QStandardItem* currentItem = mainModel->itemFromIndex(index);
	QString actionId = currentItem->data(Qt::UserRole).toString();

	StelAction* action = actionMgr->findAction(actionId);
	if (!action)
		return;
	action->setShortcut(ui->primaryShortcutEdit->getKeySequence().toString());
	action->setAltShortcut(ui->altShortcutEdit->getKeySequence().toString());
	updateShortcutsItem(action);

	// save shortcuts to file
	actionMgr->saveShortcuts();

	// nothing to apply until edits' content changes
	ui->applyButton->setEnabled(false);
	ui->restoreDefaultsButton->setEnabled(true);
}

void ShortcutsDialog::switchToEditors(const QModelIndex& index)
{
	QModelIndex mainIndex = filterModel->mapToSource(index);
	QStandardItem* item = mainModel->itemFromIndex(mainIndex);
	if (itemIsEditable(item))
	{
		ui->primaryShortcutEdit->setFocus();
	}
}

void ShortcutsDialog::createDialogContent()
{
	ui->setupUi(dialog);
	connect(ui->titleBar, &TitleBar::movedTo, this, &ShortcutsDialog::handleMovedTo);

	resetModel();
	filterModel->setSourceModel(mainModel);
	filterModel->setFilterCaseSensitivity(Qt::CaseInsensitive);
	filterModel->setSortCaseSensitivity(Qt::CaseInsensitive);
	filterModel->setDynamicSortFilter(true);
	filterModel->setSortLocaleAware(true);
	ui->shortcutsTreeView->setModel(filterModel);
	ui->shortcutsTreeView->header()->setSectionsMovable(false);
	ui->shortcutsTreeView->sortByColumn(0, Qt::AscendingOrder);

	// Kinetic scrolling
	kineticScrollingList << ui->shortcutsTreeView;
	StelGui* gui= dynamic_cast<StelGui*>(StelApp::getInstance().getGui());
	if (gui)
	{
		enableKineticScrolling(gui->getFlagUseKineticScrolling());
		connect(gui, &StelGui::flagUseKineticScrollingChanged, this, &ShortcutsDialog::enableKineticScrolling);
	}

	connect(&StelApp::getInstance(), &StelApp::languageChanged, this, &ShortcutsDialog::retranslate);
	connect(ui->shortcutsTreeView->selectionModel(), &QItemSelectionModel::currentChanged, this, &ShortcutsDialog::initEditors);
	connect(ui->shortcutsTreeView, &QTreeView::activated, this, &ShortcutsDialog::switchToEditors);
	connect(ui->lineEditSearch, &QLineEdit::textChanged, filterModel, &ShortcutsFilterModel::setFilterFixedString);
	
	// apply button logic
	connect(ui->applyButton, &QPushButton::clicked, this, &ShortcutsDialog::applyChanges);
	// restore defaults button logic
	connect(ui->restoreDefaultsButton, &QPushButton::clicked, this, &ShortcutsDialog::restoreDefaultShortcuts);
	connect(ui->restoreAllDefaultsButton, &QPushButton::clicked, this, &ShortcutsDialog::restoreAllDefaultShortcuts);
	// we need to disable all shortcut actions, so we can enter shortcuts without activating any actions
	connect(ui->primaryShortcutEdit, &ShortcutLineEdit::focusChanged, actionMgr, &StelActionMgr::setAllActionsEnabled);
	connect(ui->altShortcutEdit, &ShortcutLineEdit::focusChanged, actionMgr, &StelActionMgr::setAllActionsEnabled);
	// handling changes in editors
	connect(ui->primaryShortcutEdit, &ShortcutLineEdit::contentsChanged, this, &ShortcutsDialog::handleChanges);
	connect(ui->altShortcutEdit, &ShortcutLineEdit::contentsChanged, this, &ShortcutsDialog::handleChanges);

	QString backspaceChar;
	backspaceChar.append(QChar(0x232B)); // Erase left
	//test.append(QChar(0x2672));
	//test.append(QChar(0x267B));
	//test.append(QChar(0x267C));
	//test.append(QChar(0x21BA)); // Counter-clockwise
	//test.append(QChar(0x2221)); // Angle sign

	updateTreeData();

	// set initial focus to action search
	ui->lineEditSearch->setFocus();
}

void ShortcutsDialog::polish()
{
	ui->primaryShortcutEdit->style()->unpolish(ui->primaryShortcutEdit);
	ui->primaryShortcutEdit->style()->polish(ui->primaryShortcutEdit);
	ui->altShortcutEdit->style()->unpolish(ui->altShortcutEdit);
	ui->altShortcutEdit->style()->polish(ui->altShortcutEdit);
}

QStandardItem* ShortcutsDialog::updateGroup(const QString& group)
{
	QStandardItem* groupItem = findItemByData(QVariant(group),
	                                          Qt::UserRole);
	bool isNew = false;
	if (!groupItem)
	{
		// create new
		groupItem = new QStandardItem();
		isNew = true;
	}
	// group items aren't selectable, so reset default flag
	groupItem->setFlags(Qt::ItemIsEnabled);
	
	// setup displayed text
	groupItem->setText(q_(group));
	// store id
	groupItem->setData(group, Qt::UserRole);
	groupItem->setColumnCount(3);
	// setup bold font for group lines
	QFont rootFont = groupItem->font();
	rootFont.setBold(true);
	// Font size is 14
	rootFont.setPixelSize(StelApp::getInstance().getScreenFontSize()+1);
	groupItem->setFont(rootFont);
	if (isNew)
		mainModel->appendRow(groupItem);
	

	QModelIndex index = filterModel->mapFromSource(groupItem->index());
	ui->shortcutsTreeView->expand(index);
	ui->shortcutsTreeView->setFirstColumnSpanned(index.row(), QModelIndex(), true);
	ui->shortcutsTreeView->setRowHidden(index.row(), QModelIndex(), false);
	
	return groupItem;
}

QStandardItem* ShortcutsDialog::findItemByData(QVariant value, int role, int column) const
{
	for (int row = 0; row < mainModel->rowCount(); row++)
	{
		QStandardItem* item = mainModel->item(row, 0);
		if (!item)
			continue; //WTF?
		if (column == 0)
		{
			if (item->data(role) == value)
				return item;
		}
		
		for (int subrow = 0; subrow < item->rowCount(); subrow++)
		{
			QStandardItem* subitem = item->child(subrow, column);
			if (subitem->data(role) == value)
				return subitem;
		}
	}
	return nullptr;
}

void ShortcutsDialog::updateShortcutsItem(StelAction *action,
                                          QStandardItem *shortcutItem)
{
	QVariant shortcutId(action->getId());
	if (shortcutItem == nullptr)
	{
		// search for item
		shortcutItem = findItemByData(shortcutId, Qt::UserRole, 0);
	}
	// we didn't find item, create and add new
	QStandardItem* groupItem = nullptr;
	if (shortcutItem == nullptr)
	{
		// firstly search for group
		QVariant groupId(action->getGroup());
		groupItem = findItemByData(groupId, Qt::UserRole, 0);
		if (groupItem == nullptr)
		{
			// create and add new group to treeWidget
			groupItem = updateGroup(action->getGroup());
		}
		// create shortcut item
		shortcutItem = new QStandardItem();
		shortcutItem->setFlags(Qt::ItemIsEnabled | Qt::ItemIsSelectable);
		groupItem->appendRow(shortcutItem);
		// store shortcut id, so we can find it when shortcut changed
		shortcutItem->setData(shortcutId, Qt::UserRole);
		QStandardItem* primaryItem = new QStandardItem();
		QStandardItem* secondaryItem = new QStandardItem();
		primaryItem->setFlags(Qt::ItemIsEnabled | Qt::ItemIsSelectable);
		secondaryItem->setFlags(Qt::ItemIsEnabled | Qt::ItemIsSelectable);
		groupItem->setChild(shortcutItem->row(), 1, primaryItem);
		groupItem->setChild(shortcutItem->row(), 2, secondaryItem);
	}
	// setup properties of item
	shortcutItem->setText(action->getText());
	QModelIndex index = shortcutItem->index();
	mainModel->setData(index.sibling(index.row(), 1),
	                   action->getShortcut(), Qt::DisplayRole);
	mainModel->setData(index.sibling(index.row(), 2),
	                   action->getAltShortcut(), Qt::DisplayRole);
}

void ShortcutsDialog::restoreAllDefaultShortcuts()
{
	if (askConfirmation())
	{
		qDebug() << "[Shortcuts] restore defaults...";
		resetCollisions();
		resetModel();
		actionMgr->restoreDefaultShortcuts();
		updateTreeData();
		initEditors();
	}
	else
		qDebug() << "[Shortcuts] restore defaults is canceled...";
}

void ShortcutsDialog::restoreDefaultShortcuts()
{
	// get ids stored in tree
	QModelIndex index = filterModel->mapToSource(ui->shortcutsTreeView->currentIndex());
	if (!index.isValid())
		return;
	index = index.sibling(index.row(), 0);
	QStandardItem* currentItem = mainModel->itemFromIndex(index);
	QString actionId = currentItem->data(Qt::UserRole).toString();

	StelAction* action = actionMgr->findAction(actionId);
	if (action)
	{
		actionMgr->restoreDefaultShortcut(action);
		updateShortcutsItem(action);
		QSignalBlocker primaryBlocker(ui->primaryShortcutEdit);
		QSignalBlocker altBlocker(ui->altShortcutEdit);
		ui->primaryShortcutEdit->setContents(action->getShortcut());
		ui->altShortcutEdit->setContents(action->getAltShortcut());
		ui->primaryBackspaceButton->setEnabled(!ui->primaryShortcutEdit->isEmpty());
		ui->altBackspaceButton->setEnabled(!ui->altShortcutEdit->isEmpty());
		resetCollisions();
		ui->applyButton->setEnabled(false);
		ui->restoreDefaultsButton->setEnabled(false);
		polish();
	}
}

void ShortcutsDialog::updateTreeData()
{
	// Create shortcuts tree
	const QStringList groups = actionMgr->getGroupList();
	for (const auto& group : groups)
	{
		updateGroup(group);
		// display group's shortcuts
		const QList<StelAction*> actions = actionMgr->getActionList(group);
		for (auto* action : actions)
		{
			updateShortcutsItem(action);
		}
	}
	// adjust columns
	for(int i=0; i<3; i++)
		ui->shortcutsTreeView->resizeColumnToContents(i);
}

bool ShortcutsDialog::itemIsEditable(QStandardItem *item)
{
	if (item == nullptr) return false;
	// non-editable items(not group items) have no Qt::ItemIsSelectable flag
	return (Qt::ItemIsSelectable & item->flags());
}

void ShortcutsDialog::resetModel()
{
	mainModel->clear();
	setModelHeader();
}

void ShortcutsDialog::setModelHeader()
{
	QStringList headerLabels;
	headerLabels << q_("Action") << qc_("Primary shortcut","column name") << qc_("Alternative shortcut","column name");
	mainModel->setHorizontalHeaderLabels(headerLabels);
}
