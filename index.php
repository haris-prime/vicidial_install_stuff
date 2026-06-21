<?php
require_once __DIR__ . '/lib.php';

header('X-Content-Type-Options: nosniff');

$action = isset($_GET['action']) ? $_GET['action'] : '';

/* ----------------------------------------------------------------------------
 * AJAX endpoints (UNCHANGED). Every IP is validated by fw_valid_ip() BEFORE it
 * can reach the firewall helper.
 * -------------------------------------------------------------------------- */

if ($action === 'add' || $action === 'update') {

    $ip = fw_valid_ip($_GET['ip'] ?? '');
    if ($ip === false) {
        echo ($action === 'add') ? 'invalid---invalid' : 'invalid';
        exit;
    }
    $name = fw_clean_name($_GET['name'] ?? '');
    $temp = fw_clean_temp($_GET['temporary'] ?? 'N');
    $timestamp = date('Y-m-d H:i:s');

    $data = fw_load();

    if ($action === 'update') {
        $id = (string)($_GET['id'] ?? '');
        if (!array_key_exists($id, $data)) { echo 'invalid'; exit; }
        if (fw_ip_exists($data, $ip, $id)) { echo 'exists'; exit; }
        $data[$id] = array($ip, $name, $temp, $timestamp);
        fw_save($data);
        fw_apply($err);
        echo $timestamp;
        exit;
    }

    if (fw_ip_exists($data, $ip)) { echo 'exists---exists'; exit; }
    $id = fw_next_id($data);
    $data[$id] = array($ip, $name, $temp, $timestamp);
    fw_save($data);
    fw_apply($err);
    echo $id . '---' . $timestamp;
    exit;
}

if ($action === 'delete') {
    $id = (string)($_GET['id'] ?? '');
    $data = fw_load();
    unset($data[$id]);
    fw_save($data);
    fw_apply($err);
    echo 'ok';
    exit;
}

if ($action === 'bulk_delete') {
    $ids = explode(',', (string)($_GET['ids'] ?? ''));
    $data = fw_load();
    foreach ($ids as $id) { unset($data[trim($id)]); }
    fw_save($data);
    fw_apply($err);
    echo 'ok';
    exit;
}

if ($action === 'emptycrud') {
    fw_save(array());
    fw_apply($err);
    echo "<script>window.location = '/iptable/';</script>";
    exit;
}

/* ----------------------------------------------------------------------------
 * Page render  (glassmorphism — matched to VICIDIAL welcome.php; DOM ids /
 * classes / JS preserved so all functionality is unchanged)
 * -------------------------------------------------------------------------- */
$records = fw_load();
ksort($records, SORT_NUMERIC);
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?php echo htmlspecialchars(FW_TITLE); ?></title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  *{ box-sizing:border-box; }
  html,body{
    margin:0; min-height:100vh; width:100%; overflow-x:hidden; color:#fff;
    font-family:'Inter',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;
    -webkit-font-smoothing:antialiased;
    background:radial-gradient(circle at 18% 22%, #3b78dd 0%, #2058c4 38%, #143f95 72%, #0f2f73 100%);
    background-attachment:fixed;
  }

  /* flowing liquid blobs (same as welcome.php) */
  .blob{ position:fixed; border-radius:45% 55% 60% 40% / 50% 45% 55% 50%; filter:blur(38px); opacity:.40; z-index:0; pointer-events:none; animation:vdfloat 16s ease-in-out infinite; }
  .blob.b1{ width:320px;height:320px; top:-60px; left:6%;  background:linear-gradient(135deg,#a9c6ff,#5b8bf0); animation-delay:0s; }
  .blob.b2{ width:380px;height:380px; bottom:-90px; left:2%; background:linear-gradient(135deg,#7fa9f7,#3f6fe0); animation-delay:-4s; }
  .blob.b3{ width:300px;height:300px; top:8%;  right:8%;  background:linear-gradient(135deg,#bcd2ff,#6f97ee); animation-delay:-8s; }
  .blob.b4{ width:420px;height:420px; bottom:-120px; right:-40px; background:linear-gradient(135deg,#9dc0ff,#4f7be8); animation-delay:-2s; }
  .blob.b5{ width:220px;height:220px; top:42%; left:40%; background:linear-gradient(135deg,#c7dbff,#82a6f2); opacity:.25; animation-delay:-6s; }
  @keyframes vdfloat{ 0%,100%{transform:translateY(0) rotate(0deg);} 50%{transform:translateY(-26px) rotate(8deg);} }

  .main{
    position:relative; z-index:2;
    width:min(1120px,92%); margin:46px auto; padding:30px 32px 36px;
    border-radius:24px;
    background:rgba(255,255,255,0.12);
    backdrop-filter:blur(20px) saturate(135%);
    -webkit-backdrop-filter:blur(20px) saturate(135%);
    border:1px solid rgba(255,255,255,0.28);
    box-shadow:0 24px 60px rgba(7,18,48,0.45), inset 0 1px 0 rgba(255,255,255,0.25);
    animation:vdrise .6s cubic-bezier(0.22,1,0.36,1) both;
  }
  @keyframes vdrise{ from{opacity:0; transform:translateY(18px) scale(.98);} to{opacity:1; transform:translateY(0) scale(1);} }

  .topbar{ display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:14px; margin-bottom:24px; }
  .brand-title{ font-size:27px; font-weight:700; letter-spacing:.2px; color:#fff; }
  .brand-sub{ margin-top:5px; font-size:11px; font-weight:500; letter-spacing:.22em; text-transform:uppercase; color:rgba(255,255,255,0.62); }
  .actions{ display:flex; align-items:center; gap:14px; }
  #status{ display:none; color:#d6ffe4; font-weight:600; font-size:13px; }

  .grid-wrap{ overflow-x:auto; }
  .tab{ width:100%; min-width:680px; border-collapse:separate; border-spacing:0 12px; }
  .tab th,.tab td{ padding:14px 16px; text-align:center; vertical-align:middle; border:none; }
  .head-row th{ color:rgba(255,255,255,0.72); font-weight:600; font-size:12px; text-transform:uppercase; letter-spacing:.07em; padding-top:0; padding-bottom:4px; }

  .tab tr:not(.head-row){ background:rgba(255,255,255,0.10); transition:background .18s; }
  .tab tr:not(.head-row):hover{ background:rgba(255,255,255,0.16); }
  .tab tr:not(.head-row) td:first-child{ border-top-left-radius:14px; border-bottom-left-radius:14px; }
  .tab tr:not(.head-row) td:last-child{ border-top-right-radius:14px; border-bottom-right-radius:14px; }
  .add-row{ background:rgba(255,255,255,0.06) !important; }

  .inp{
    width:100%; padding:10px 12px; font-size:14px; color:#fff;
    background:rgba(255,255,255,0.16); border:1px solid rgba(255,255,255,0.30);
    border-radius:10px; transition:all .18s;
  }
  .inp::placeholder{ color:rgba(255,255,255,0.55); }
  .inp:focus{ outline:none; border-color:#fff; background:rgba(255,255,255,0.24); box-shadow:0 0 0 3px rgba(255,255,255,0.18); }

  input[type=radio],input[type=checkbox]{ accent-color:#2058c4; width:16px; height:16px; cursor:pointer; vertical-align:middle; }

  [id^="time-"]{ color:rgba(255,255,255,0.70); font-size:13px; }
  .ph{ color:rgba(255,255,255,0.45); }

  /* buttons — primary navy + white secondary + red danger (welcome.php language) */
  .butt{
    border:none; border-radius:11px; padding:10px 18px; font-size:14px; font-weight:600;
    cursor:pointer; text-decoration:none; display:inline-block; margin:3px 4px;
    transition:transform .18s ease, background .18s ease, box-shadow .18s ease;
    background:#0f1b3d; color:#fff; box-shadow:0 10px 24px rgba(8,16,40,0.42);
  }
  .butt:hover{ background:#18295c; transform:translateY(-2px); box-shadow:0 14px 30px rgba(8,16,40,0.55); }
  .butt:active{ transform:translateY(0); }
  .butt[value="Add Record"]{ background:rgba(255,255,255,0.92); color:#16285a; box-shadow:0 10px 24px rgba(0,0,0,0.18); }
  .butt[value="Add Record"]:hover{ background:#fff; box-shadow:0 14px 30px rgba(0,0,0,0.25); }
  .butt[value="Delete"],.butt.danger{ background:#d83b34; color:#fff; box-shadow:0 10px 24px rgba(170,40,33,0.42); }
  .butt[value="Delete"]:hover,.butt.danger:hover{ background:#e8493f; box-shadow:0 14px 30px rgba(170,40,33,0.55); }
</style>
</head>
<body>
<div class="blob b1"></div><div class="blob b2"></div><div class="blob b3"></div><div class="blob b4"></div><div class="blob b5"></div>

<div class="main">
  <div class="topbar">
    <div>
      <div class="brand-title"><?php echo htmlspecialchars(FW_TITLE); ?></div>
      <div class="brand-sub">Whitelist Management</div>
    </div>
    <div class="actions">
      <span id="status"></span>
      <button class="butt danger" onclick="bulkDelete()">Bulk Delete</button>
    </div>
  </div>

  <div class="grid-wrap">
  <table class="tab" id="grid">
    <tr class="head-row">
      <th><input type="checkbox" onclick="toggle(this);" /></th>
      <th>Name</th><th>IP</th><th>Temporary</th><th>Timestamp</th><th>Action</th>
    </tr>
<?php foreach ($records as $k => $v):
        $name = htmlspecialchars($v[1], ENT_QUOTES);
        $ipv  = htmlspecialchars($v[0], ENT_QUOTES);
        $ts   = htmlspecialchars($v[3], ENT_QUOTES);
?>
    <tr id="row-<?php echo (int)$k; ?>">
      <td><input type="checkbox" class="index" name="to_delete" id="<?php echo (int)$k; ?>" /></td>
      <td><input type="text" id="name-<?php echo (int)$k; ?>" class="inp" value="<?php echo $name; ?>" /></td>
      <td><input type="text" id="ip-<?php echo (int)$k; ?>" class="inp" value="<?php echo $ipv; ?>" /></td>
      <td>
        <input type="radio" name="temp-<?php echo (int)$k; ?>" id="yes-<?php echo (int)$k; ?>" <?php if ($v[2]==='Y') echo 'checked'; ?> />Yes&nbsp;&nbsp;
        <input type="radio" name="temp-<?php echo (int)$k; ?>" id="no-<?php echo (int)$k; ?>" <?php if ($v[2]==='N') echo 'checked'; ?> />No
      </td>
      <td><div id="time-<?php echo (int)$k; ?>"><?php echo $ts; ?></div></td>
      <td>
        <input type="button" class="butt" value="Update" onclick="update(<?php echo (int)$k; ?>)" />
        <input type="button" class="butt" value="Delete" onclick="del(<?php echo (int)$k; ?>)" />
      </td>
    </tr>
<?php endforeach; ?>
    <tr class="add-row">
      <td></td>
      <td><input type="text" id="add-name" class="inp" placeholder="Name" /></td>
      <td><input type="text" id="add-ip" class="inp" placeholder="IP address" /></td>
      <td><input type="radio" name="add-temp" id="add-yes" />Yes&nbsp;&nbsp;<input type="radio" name="add-temp" id="add-no" checked />No</td>
      <td><span class="ph">—</span></td>
      <td><input type="button" class="butt" value="Add Record" onclick="add()" /></td>
    </tr>
  </table>
  </div>
</div>

<script>
function getCheckedBoxes(name){var b=document.getElementsByName(name),r=[];for(var i=0;i<b.length;i++){if(b[i].checked)r.push(b[i]);}return r.length?r:null;}
function toggle(src){var b=document.querySelectorAll('input[type="checkbox"]');for(var i=0;i<b.length;i++){if(b[i]!=src)b[i].checked=src.checked;}}
function flash(msg){var s=document.getElementById('status');s.innerHTML=msg;s.style.display='inline';setTimeout(function(){s.innerHTML='';s.style.display='none';},3000);}
function bulkDelete(){
  if(!confirm('Are you sure?')){alert('Ok, next time be careful.');return;}
  var c=getCheckedBoxes('to_delete');if(!c){return;}
  var ids=[];for(var i=0;i<c.length;i++){ids.push(c[i].id);}
  var x=new XMLHttpRequest();
  x.onreadystatechange=function(){if(this.readyState==4&&this.status==200){window.location.reload();}};
  x.open('GET','index.php?action=bulk_delete&ids='+ids.join(','),true);x.send();
}
function update(id){
  var name=document.getElementById('name-'+id).value;
  var ip=document.getElementById('ip-'+id).value;
  var temporary=document.getElementById('yes-'+id).checked?'Y':'N';
  var x=new XMLHttpRequest();
  x.onreadystatechange=function(){
    if(this.readyState==4&&this.status==200){
      if(this.responseText=='exists'){flash('IP Already Exists');}
      else if(this.responseText=='invalid'){flash('Invalid IP');}
      else{document.getElementById('time-'+id).innerHTML=this.responseText;flash('Updated');}
    }
  };
  x.open('GET','index.php?action=update&id='+id+'&name='+encodeURIComponent(name)+'&ip='+encodeURIComponent(ip)+'&temporary='+temporary,true);
  x.send();
}
function del(id){
  var x=new XMLHttpRequest();
  x.onreadystatechange=function(){
    if(this.readyState==4&&this.status==200){
      var row=document.getElementById('row-'+id);row.parentNode.removeChild(row);flash('Deleted');
    }
  };
  x.open('GET','index.php?action=delete&id='+id,true);x.send();
}
function add(){
  var name=document.getElementById('add-name').value;
  var ip=document.getElementById('add-ip').value;
  var temporary=document.getElementById('add-yes').checked?'Y':'N';
  var x=new XMLHttpRequest();
  x.onreadystatechange=function(){
    if(this.readyState==4&&this.status==200){
      var ret=this.responseText.split('---');
      if(ret[0]=='exists'){flash('IP Already Exists');return;}
      if(ret[0]=='invalid'){flash('Invalid IP');return;}
      var id=ret[0],timestamp=ret[1];
      var table=document.getElementById('grid');
      var row=table.insertRow(table.rows.length-1);
      row.id='row-'+id;
      var yescheck=(temporary=='Y')?'checked':'';
      var nocheck=(temporary=='N')?'checked':'';
      row.insertCell(0).innerHTML="<input type='checkbox' class='index' name='to_delete' id='"+id+"' />";
      row.insertCell(1).innerHTML="<input type='text' id='name-"+id+"' class='inp' value='"+name.replace(/'/g,"&#39;")+"' />";
      row.insertCell(2).innerHTML="<input type='text' id='ip-"+id+"' class='inp' value='"+ip.replace(/'/g,"&#39;")+"' />";
      row.insertCell(3).innerHTML="<input type='radio' name='temp-"+id+"' id='yes-"+id+"' "+yescheck+" />Yes&nbsp;&nbsp;<input type='radio' name='temp-"+id+"' id='no-"+id+"' "+nocheck+" />No";
      row.insertCell(4).innerHTML="<div id='time-"+id+"'>"+timestamp+"</div>";
      row.insertCell(5).innerHTML="<input type='button' class='butt' value='Update' onclick='update("+id+")' /><input type='button' class='butt' value='Delete' onclick='del("+id+")' />";
      document.getElementById('add-name').value='';
      document.getElementById('add-ip').value='';
      document.getElementById('add-yes').checked=false;
      document.getElementById('add-no').checked=true;
      flash('Added');
    }
  };
  x.open('GET','index.php?action=add&name='+encodeURIComponent(name)+'&ip='+encodeURIComponent(ip)+'&temporary='+temporary,true);
  x.send();
}
</script>
</body>
</html>