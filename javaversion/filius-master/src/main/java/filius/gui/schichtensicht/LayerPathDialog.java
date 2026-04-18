package filius.gui.schichtensicht;

import java.awt.BorderLayout;
import java.awt.Dimension;
import java.awt.Toolkit;

import javax.swing.JDialog;
import javax.swing.JFrame;

import filius.rahmenprogramm.I18n;
import filius.software.system.SystemSoftware;

/**
 * This class is used as a top container for the local or global layer path view.
 * 
 * @author Christoph Irniger
 */
public class LayerPathDialog extends JDialog implements I18n {
    /** the corresponding JPanel which is contained in this JDialog */
    private final LocalLayerPathPanel LOCAL_LAYER_PATH_PANEL;

    public LayerPathDialog(JFrame owner, String interfaceId, SystemSoftware systemSoftware, int selectedFrameNumber,
            GlobalLayerPath globalLayerPath, boolean isMainNode) {
        super(owner, true);

        // user can resize the JDialog
        setResizable(true);

        // initialise BorderLayout
        BorderLayout borderLayout = new BorderLayout(10, 10);
        setLayout(borderLayout);

        LOCAL_LAYER_PATH_PANEL = new LocalLayerPathPanel(owner, interfaceId, systemSoftware, selectedFrameNumber,
                globalLayerPath, isMainNode);

        // set size and positioning properties of outer JDialog
        Dimension screenSize = Toolkit.getDefaultToolkit().getScreenSize();
        setLocation(screenSize.width / 6, screenSize.height / 6);
        int dialogWidth = LOCAL_LAYER_PATH_PANEL.getSizeOfMessageDetailsTable().width + 30;
        int dialogHeight = LOCAL_LAYER_PATH_PANEL.getSizeOfMessageDetailsTable().height
                + LOCAL_LAYER_PATH_PANEL.getDefaultDividerLocation() + 100;
        setPreferredSize(new Dimension(dialogWidth, dialogHeight));
        setMinimumSize(new Dimension(dialogWidth, dialogHeight));

        // Panel is in the center of the BorderLayout
        add(LOCAL_LAYER_PATH_PANEL, BorderLayout.CENTER);

        // When in global view this Dialog will be set visible inside the
        // GlobalLayerPath class
        if (globalLayerPath == null) {
            setVisible(true);
        }
    }

    protected LocalLayerPathPanel getLocalLayerPathPanel() {
        return this.LOCAL_LAYER_PATH_PANEL;
    }
}
