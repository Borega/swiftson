/*
 ** This file is part of Filius, a network construction and simulation software.
 ** 
 ** Originally created at the University of Siegen, Institute "Didactics of
 ** Informatics and E-Learning" by a students' project group:
 **     members (2006-2007): 
 **         André Asschoff, Johannes Bade, Carsten Dittich, Thomas Gerding,
 **         Nadja Haßler, Ernst Johannes Klebert, Michell Weyer
 **     supervisors:
 **         Stefan Freischlad (maintainer until 2009), Peer Stechert
 ** Project is maintained since 2010 by Christian Eibl <filius@c.fameibl.de>
 **         and Stefan Freischlad
 ** Filius is free software: you can redistribute it and/or modify
 ** it under the terms of the GNU General Public License as published by
 ** the Free Software Foundation, either version 2 of the License, or
 ** (at your option) version 3.
 ** 
 ** Filius is distributed in the hope that it will be useful,
 ** but WITHOUT ANY WARRANTY; without even the implied
 ** warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 ** PURPOSE. See the GNU General Public License for more details.
 ** 
 ** You should have received a copy of the GNU General Public License
 ** along with Filius.  If not, see <http://www.gnu.org/licenses/>.
 */
package filius.gui;

import java.awt.Dimension;
import java.awt.Image;
import java.awt.Rectangle;
import java.awt.Toolkit;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.util.Locale;
import java.util.ResourceBundle;

import javax.swing.Box;
import javax.swing.JButton;
import javax.swing.JCheckBox;
import javax.swing.JComboBox;
import javax.swing.JDialog;
import javax.swing.JLabel;

import filius.Main;
import filius.rahmenprogramm.IconMode;
import filius.rahmenprogramm.Information;

@SuppressWarnings("serial")
public class LanguageSelectionDialog extends JDialog {

    private static final String FRANCAIS = "Français";
    private static final String ENGLISH = "English";
    private static final String DEUTSCH = "Deutsch";

    private JLabel selectLanguageLabel = new JLabel();
    private JComboBox<String> languageSelection = new JComboBox<>();
    private JLabel selectIconModeLabel = new JLabel();
    private JComboBox<String> iconModeSelection = new JComboBox<>();
    private JCheckBox layerVisualization = new JCheckBox();
    private JLabel restartHint = new JLabel();
    private JButton confirm = new JButton();
    private JButton confirmAndExit = new JButton();
    private JButton cancel = new JButton();
    private Box buttonBox = Box.createHorizontalBox();

    private LanguageSelectionDialog(boolean restartMode) {
        super(restartMode ? JMainFrame.getJMainFrame() : null);
        this.setModal(true);
        Image image = Toolkit.getDefaultToolkit()
                .getImage(LanguageSelectionDialog.class.getResource("/gfx/hardware/kabel.png"));
        this.setIconImage(image);
        if (restartMode) {
            this.setTitle("Einstellungen / Settings / Paramètres");
        } else {
            this.setTitle("Sprache / Language / Langue");
        }
        this.setResizable(false);
        initialize(restartMode);
        initializeText(Information.getInformation().getLocaleOrDefault());
        initializeSettings();
    }

    private void initializeSettings() {
        languageSelection.setSelectedItem(localeToLanguage(Information.getInformation().getLocaleOrDefault()));
        if (Information.getInformation().getIconMode() == IconMode.DEFAULT) {
            iconModeSelection.setSelectedIndex(0);
        } else if (Information.getInformation().getIconMode() == IconMode.ENTERPRISE) {
            iconModeSelection.setSelectedIndex(1);
        } else {
            iconModeSelection.setSelectedIndex(2);
        }
        layerVisualization.setSelected(Information.getInformation().isLayerVisualization());
    }

    private void initializeText(Locale locale) {
        ResourceBundle bundle = ResourceBundle.getBundle("filius.messages.MessagesBundle", locale);

        selectLanguageLabel.setText(bundle.getString("languageSelection_msg1"));
        int selectedIndex = languageSelection.getSelectedIndex();
        languageSelection.removeAllItems();
        languageSelection.addItem(DEUTSCH);
        languageSelection.addItem(ENGLISH);
        languageSelection.addItem(FRANCAIS);
        languageSelection.setSelectedIndex(selectedIndex);

        selectIconModeLabel.setText(bundle.getString("settings_msg1"));
        selectedIndex = iconModeSelection.getSelectedIndex();
        iconModeSelection.removeAllItems();
        ;
        iconModeSelection.addItem(bundle.getString("settings_msg2"));
        iconModeSelection.addItem(bundle.getString("settings_msg3"));
        iconModeSelection.addItem(bundle.getString("settings_msg4"));
        iconModeSelection.setSelectedIndex(selectedIndex);

        layerVisualization.setText(bundle.getString("settings_msg5"));

        restartHint.setText("<html>" + bundle.getString("languageSelection_msg2") + "</html>");
        confirm.setText(bundle.getString("languageSelection_msg3"));
        confirmAndExit.setText(bundle.getString("languageSelection_msg4"));
        cancel.setText(bundle.getString("languageSelection_msg5"));

        buttonBox.updateUI();
    }

    public static void selectLanguage(boolean restart) {
        LanguageSelectionDialog instance = new LanguageSelectionDialog(restart);
        instance.setVisible(true);
    }

    private void apply() {
        String selectedValue = (String) languageSelection.getSelectedItem();
        Information.getInformation().setLocale(languageToLocale(selectedValue));
        switch (iconModeSelection.getSelectedIndex()) {
        case 1:
            Information.getInformation().setIconMode(IconMode.ENTERPRISE);
            break;
        case 2:
            Information.getInformation().setIconMode(IconMode.SYMBOL);
            break;
        default:
            Information.getInformation().setIconMode(IconMode.DEFAULT);
        }
        Information.getInformation().setLayerVisualization(layerVisualization.isSelected());
    }

    private Locale languageToLocale(String language) {
        Locale locale = Locale.UK;
        if (FRANCAIS.equals(language)) {
            locale = Locale.FRANCE;
        } else if (DEUTSCH.equals(language)) {
            locale = Locale.GERMANY;
        }
        return locale;
    }

    private String localeToLanguage(Locale locale) {
        String language;
        if (null == locale || Locale.UK.getCountry().equals(locale.getCountry())) {
            language = ENGLISH;
        } else if (Locale.FRANCE.getCountry().equals(locale.getCountry())) {
            language = FRANCAIS;
        } else {
            language = DEUTSCH;
        }
        return language;
    }

    private void initialize(boolean restartMode) {
        Box verticalBox = Box.createVerticalBox();
        verticalBox.setPreferredSize(new Dimension(400, 320));
        getContentPane().add(verticalBox);
        pack();

        if (restartMode) {
            Rectangle mainFrameBounds = JMainFrame.getJMainFrame().getBounds();
            setLocation(mainFrameBounds.x + mainFrameBounds.width / 2 - getWidth() / 2,
                    mainFrameBounds.y + mainFrameBounds.height / 2 - getHeight() / 2);
        } else {
            setLocation((getToolkit().getScreenSize().width - getWidth()) / 2,
                    (getToolkit().getScreenSize().height - getHeight()) / 2);
        }

        verticalBox.add(Box.createVerticalStrut(10));

        Box languageLabelBox = Box.createHorizontalBox();
        languageLabelBox.add(Box.createHorizontalStrut(10));
        languageLabelBox.add(selectLanguageLabel);
        languageLabelBox.add(Box.createGlue());
        verticalBox.add(languageLabelBox);

        verticalBox.add(Box.createVerticalStrut(10));
        languageSelection.setMaximumSize(new Dimension(380, 30));
        languageSelection.setPreferredSize(new Dimension(380, 30));
        languageSelection.addActionListener(new ActionListener() {

            @Override
            public void actionPerformed(ActionEvent e) {
                LanguageSelectionDialog.this
                        .initializeText(languageToLocale((String) languageSelection.getSelectedItem()));
            }
        });

        Box languageSelectBox = Box.createHorizontalBox();
        languageSelectBox.add(Box.createHorizontalStrut(10));
        languageSelectBox.add(languageSelection);
        languageSelectBox.add(Box.createGlue());
        verticalBox.add(languageSelectBox);

        if (restartMode) {
            verticalBox.add(Box.createVerticalStrut(10));

            Box iconModeLabelBox = Box.createHorizontalBox();
            iconModeLabelBox.add(Box.createHorizontalStrut(10));
            iconModeLabelBox.add(selectIconModeLabel);
            iconModeLabelBox.add(Box.createGlue());
            verticalBox.add(iconModeLabelBox);

            verticalBox.add(Box.createVerticalStrut(10));
            iconModeSelection.setMaximumSize(new Dimension(380, 30));
            iconModeSelection.setPreferredSize(new Dimension(380, 30));

            Box iconModeSelectBox = Box.createHorizontalBox();
            iconModeSelectBox.add(Box.createHorizontalStrut(10));
            iconModeSelectBox.add(iconModeSelection);
            iconModeSelectBox.add(Box.createGlue());
            verticalBox.add(iconModeSelectBox);
        }

        if (restartMode) {
            verticalBox.add(Box.createVerticalStrut(10));

            Box layerVisualizationBox = Box.createHorizontalBox();
            layerVisualizationBox.add(Box.createHorizontalStrut(10));
            layerVisualizationBox.add(layerVisualization);
            layerVisualizationBox.add(Box.createGlue());
            verticalBox.add(layerVisualizationBox);

            verticalBox.add(Box.createVerticalStrut(10));
            layerVisualization.setMaximumSize(new Dimension(380, 30));
            layerVisualization.setPreferredSize(new Dimension(380, 30));
        }

        if (restartMode) {
            verticalBox.add(Box.createVerticalStrut(10));

            Box hintBox = Box.createHorizontalBox();
            hintBox.add(Box.createHorizontalStrut(10));
            // hintBox.setBorder(BorderFactory.createEtchedBorder());
            restartHint.setPreferredSize(new Dimension(350, 60));
            restartHint.setSize(new Dimension(350, 60));
            restartHint.setMinimumSize(new Dimension(350, 60));
            hintBox.add(restartHint);
            hintBox.add(Box.createGlue());
            verticalBox.add(hintBox);

            verticalBox.add(Box.createVerticalStrut(10));
        } else {
            verticalBox.add(Box.createVerticalStrut(90));
        }

        // buttonBox.setAlignmentX(Box.RIGHT_ALIGNMENT);
        // buttonBox.setBorder(BorderFactory.createEtchedBorder());
        buttonBox.setSize(new Dimension(390, 50));
        buttonBox.setPreferredSize(new Dimension(390, 50));
        buttonBox.setMinimumSize(new Dimension(390, 50));
        if (restartMode) {
            cancel.setPreferredSize(new Dimension(120, 30));
            cancel.addActionListener(new ActionListener() {

                @Override
                public void actionPerformed(ActionEvent e) {
                    LanguageSelectionDialog.this.setVisible(false);
                }
            });
            buttonBox.add(cancel);
            buttonBox.add(Box.createHorizontalStrut(10));

            confirmAndExit.addActionListener(new ActionListener() {

                @Override
                public void actionPerformed(ActionEvent e) {
                    LanguageSelectionDialog.this.apply();
                    Main.beenden();
                }
            });
            buttonBox.add(confirmAndExit);
        } else {
            confirm.setPreferredSize(new Dimension(250, 30));
            confirm.addActionListener(new ActionListener() {

                @Override
                public void actionPerformed(ActionEvent e) {
                    LanguageSelectionDialog.this.apply();
                    LanguageSelectionDialog.this.setVisible(false);
                }
            });
            buttonBox.add(confirm);
        }

        verticalBox.add(Box.createVerticalGlue());

        verticalBox.add(buttonBox);
    }
}
