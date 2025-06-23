// Function to create and show the info popup
function showWardInfo(wardNo, wardName, description) {
    // Strip leading number and dot, and any 'WARD NO:' or 'Ward' prefix from wardName
    let cleanWardName = wardName.replace(/^\d+\.\s*/, '').replace(/^(WARD\s+NO:|Ward\s+\d+:)\s*/i, '');

    // Create popup container
    const popup = document.createElement('div');
    popup.className = 'ward-info-popup';
    popup.style.cssText = `
        position: fixed;
        top: 50%;
        left: 50%;
        transform: translate(-50%, -50%);
        background: white;
        padding: 20px;
        border-radius: 8px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        z-index: 1000;
        max-width: 80%;
        max-height: 80vh;
        overflow-y: auto;
    `;

    // Create close button
    const closeBtn = document.createElement('button');
    closeBtn.textContent = '×';
    closeBtn.style.cssText = `
        position: absolute;
        right: 10px;
        top: 10px;
        border: none;
        background: none;
        font-size: 24px;
        cursor: pointer;
    `;
    closeBtn.onclick = () => popup.remove();

    // Create content
    const content = document.createElement('div');
    content.innerHTML = `
        <h2>Ward ${wardNo}: ${cleanWardName}</h2>
        ${description ? `<p><strong>Description:</strong> ${description}</p>` : ''}
    `;

    popup.appendChild(closeBtn);
    popup.appendChild(content);
    document.body.appendChild(popup);

    // Add overlay
    const overlay = document.createElement('div');
    overlay.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background: rgba(0,0,0,0.5);
        z-index: 999;
    `;
    overlay.onclick = () => {
        popup.remove();
        overlay.remove();
    };
    document.body.appendChild(overlay);
}

// Function to handle ward click events
function handleWardClick(event) {
    const wardNo = event.target.feature.properties.Ward_No;
    const wardName = event.target.feature.properties.Name;
    const description = event.target.feature.properties.Description;
    
    // Ensure ward number is a string and remove any leading zeros
    const normalizedWardNo = String(wardNo).replace(/^0+/, '');
    console.log(`Clicked ward ${normalizedWardNo}`);
    
    showWardInfo(normalizedWardNo, wardName, description);
}

// Export the click handler function
window.handleWardClick = handleWardClick; 